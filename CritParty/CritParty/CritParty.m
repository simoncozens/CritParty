//
//  CritParty.m
//  CritParty
//
//  Created by Simon Cozens on 27/05/2020.
//Copyright © 2020 Simon Cozens. All rights reserved.
//

#import "CritParty.h"
#import "CritParty+Observers.h"
#import "CritParty+FontTransfer.h"

@implementation CritParty
@synthesize factory = _factory;

NSString* stunServer = @"stun:critparty.corvelsoftware.co.uk";
NSString* turnServer = @"turn:critparty.corvelsoftware.co.uk";

- (id) init {
	self = [super init];
	if (self) {
		NSLog(@"Crit party is initing");
		NSBundle *thisBundle = [NSBundle bundleForClass:[self class]];
		NSArray *arrayOfStuff;
		[thisBundle loadNibNamed:@"CritPartyWindow" owner:self topLevelObjects:&arrayOfStuff];
		NSUInteger viewIndex = [arrayOfStuff indexOfObjectPassingTest:^BOOL (id obj, NSUInteger idx, BOOL *stop) {
			return [obj isKindOfClass:[NSWindow class]];
		}];
		critPartyWindow = [arrayOfStuff objectAtIndex:viewIndex];
		[connectButton setTarget:self];
		[connectButton setAction:@selector(connectButton:)];
		_factory = [[RTC_OBJC_TYPE(RTCPeerConnectionFactory) alloc] init];
		guestUsers = [[NSMutableDictionary alloc] init];
		peerIds = [[NSMutableDictionary alloc] init];
		answerQueue = [[NSMutableDictionary alloc] init];
		outgoingQueue = [[NSMutableArray alloc] init];
		guestIceCandidateQueue = [[NSMutableArray alloc] init];
		[shareJoinTab setDelegate:self];
		connected = false;
		cursorColor = 0;
		cursors = [[NSMutableDictionary alloc] init];
		pauseNotifications = false;

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mouseMoved:) name:@"mouseMovedNotification" object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mouseMoved:) name:@"mouseDraggedNotification" object:nil];

		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mouseMoved:) name:@"GSUpdateInterface" object:nil];
		[GSCallbackHandler addCallback:self forOperation:GSDrawForegroundCallbackName];

		SCLog(@"Crit party init done");
	}
	return self;
}

- (NSUInteger) interfaceVersion {
	// Distinguishes the API verison the plugin was built for. Return 1.
	return 1;
}

- (void) loadPlugin {
	// Set up stuff
	SCLog(@"Crit party loading");
	NSMenuItem* menuItem = [[NSMenuItem alloc] initWithTitle:@"CritParty" action:@selector(startCritParty) keyEquivalent:@"p"];
	[menuItem setTarget:self];
	NSMenuItem* editMenu = [[[NSApplication sharedApplication] mainMenu] itemAtIndex:2];
	[editMenu.submenu addItem:menuItem];
}

- (void) startCritParty {
	[critPartyWindow makeKeyAndOrderFront:nil];
}

/// MARK: - Boring UI Stuff
- (IBAction)connectButton:(id)sender {
	if (!connected) {
		if ([shareJoinTab indexOfTabViewItem:[shareJoinTab selectedTabViewItem]] == 0) {
			[self beginSharing];
		} else {
			mode = CritPartyModeGuest;
			[self joinAsGuest];
		}
	} else {
		[self doDisconnect];
	}
}

- (void)doDisconnect {
	if (mode == CritPartyModeHost) {
		for (NSString* s in guestUsers) {
			NSDictionary* d = guestUsers[s];
			if (d[@"dataChannel"]) { [(RTCDataChannel*)d[@"dataChannel"] close]; }
			if (d[@"peerConnection"]) { [(RTCPeerConnection*)d[@"peerConnection"] close]; }
		}
		[guestUsers removeAllObjects];
	} else {
		if (hostDataChannel) { [hostDataChannel close]; }
		if (hostPeerConnection) { [hostPeerConnection close]; }
		hostDataChannel = nil;
		hostPeerConnection = nil;
	}
	[answerQueue removeAllObjects];
	[guestIceCandidateQueue removeAllObjects];
	[outgoingQueue removeAllObjects];
	[self.client disconnect];
	[self unlockInterface];
}

- (void)lockInterface {
	connected = true;
	dispatch_async(dispatch_get_main_queue(), ^{

		[self->connectButton setTitle:@"Disconnect"];
		[self->hostUsernameField setEnabled:false];
		[self->hostPassword setEnabled:false];
		[self->guestUsernameField setEnabled:false];
		[self->guestPassword setEnabled:false];
		[self->guestSessionID setEnabled:false];
	});
}

- (void)unlockInterface {
	connected = false;
	dispatch_async(dispatch_get_main_queue(), ^{
		[self->connectButton setTitle:@"Connect"];
		[self->hostUsernameField setEnabled:true];
		[self->hostPassword setEnabled:true];
		[self->guestUsernameField setEnabled:true];
		[self->guestPassword setEnabled:true];
		[self->guestSessionID setEnabled:true];
	});
}

- (BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(NSTabViewItem *)tabViewItem {
	return !connected;
}

- (void)appendMessage:(NSString *)message {
	dispatch_async(dispatch_get_main_queue(), ^{
		[self->textbox setString:[[
								   [self->textbox string] stringByAppendingString:message]
								  stringByAppendingString:@"\n"]];
	});
}

- (NSColor*)getNewCursorColor {
	switch (++cursorColor % 6) {
	case 0: return [NSColor redColor];
	case 1: return [NSColor blueColor];
	case 2: return [NSColor greenColor];
	case 3: return [NSColor orangeColor];
	case 4: return [NSColor yellowColor];
	case 5: return [NSColor purpleColor];
	}
	return [NSColor grayColor];
}

- (NSViewController<GSGlyphEditViewControllerProtocol> *)editViewController {
	GSDocument* currentDocument = [(GSApplication *)[NSApplication sharedApplication] currentFontDocument];
	NSWindowController<GSWindowControllerProtocol> *windowController = [currentDocument windowController];
	NSViewController<GSGlyphEditViewControllerProtocol> *editViewController = [windowController activeEditViewController];
	return editViewController;
}

/// MARK: - Crit Party Implementation

- (void) beginSharing {
	mode = CritPartyModeHost;
	myusername = [hostUsernameField stringValue];
	// Creating the client will kick off the connection.
	_client = [[SignalingClientHost alloc]
			   initWithDelegate:self
			   username:[hostUsernameField stringValue]
			   password:[hostPassword stringValue]
			   ];
	// XXX Should be the one in the list
	GSDocument* currentDocument = [(GSApplication *)[NSApplication sharedApplication] currentFontDocument];
	if (!currentDocument) {
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:@"Open a document first"];
		[alert setInformativeText:@"You don't have anything to share at the moment."];
		[alert addButtonWithTitle:@"Ok"];
		[alert runModal];
		return;
	}
	sharedFont = currentDocument.font;
	if (![self editViewController]) {
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:@"Open a tab first"];
		[alert setInformativeText:@"You don't have anything to share at the moment."];
		[alert addButtonWithTitle:@"Ok"];
		[alert runModal];
		return;
	}
	[self addObserversToLayer:[self editViewController].activeLayer];
	[self addObserversToGraphicView:[self editViewController].graphicView];
	[self lockInterface];
}

- (void) joinAsGuest {
	mode = CritPartyModeGuest;
	NSString* sid = [guestSessionID stringValue];
	NSString* username = [guestUsernameField stringValue];
	NSString* password = [guestPassword stringValue];
	myusername = [guestUsernameField stringValue];
	
	[self makeOfferWithCompletion:^void (RTCSessionDescription* offer) {
		self->_client = [[SignalingClientGuest alloc]
						 initWithDelegate:self username:username
						 password:password sessionid:sid offer:offer];
	}];
}

- (void) newConnectionEstablishedForUser:(NSString*) username {
	if(!guestUsers[username]) {
		[self handleConnectionError:@"Lost track of who just joined"];
		return;
	}
	NSString* message = [username stringByAppendingString:@" has joined"];
	[self appendMessage:message];
	// Tell others.
	[self sendToEveryone:@{ @"message": message }];

	// Send the glyphs file down their channel
	[self sendFont:sharedFont toUsername:username];
}

- (void) gotMessage:(NSDictionary*)d {
	if (![d[@"type"] isEqualToString:@"cursor"]) {
		SCLog(@"Got message on data channel %@", d);
	}
	if (d[@"message"]) {
		NSString* msg;
		if (d[@"from"]) {
			msg = [NSString stringWithFormat:@"%@: %@", d[@"from"], d[@"message"]];
		} else {
			msg = d[@"message"];
		}
		[self appendMessage:msg];
		if (mode == CritPartyModeHost) {
			if ([d[@"from"] isEqualToString:myusername]) {
				return;
			}
			[self sendToEveryone:d];
		}
	} else if ([d[@"type"] isEqualToString:@"glyphsfile"]) {
		[self handleIncomingFontChunk:d];
	} else if ([d[@"type"] isEqualToString:@"setuptabs"]) {
		[self sendTabToUser:d[@"from"]];
	} else if ([d[@"type"] isEqualToString:@"tab"]) {
		[self setupTab:d];
	} else if ([d[@"type"] isEqualToString:@"cursor"]) {
		[self setCursor:d];
		if (mode == CritPartyModeHost) {
			[self sendToEveryone:d];
		}
	} else if ([d[@"type"] isEqualToString:@"layer"]) {
		SCLog(@"Got a layer from %@", d[@"from"]);
		if (!([d[@"from"] isEqualToString: myusername])) {
			SCLog(@"Got a layer from %@", d[@"from"]);
			[self updateLayer:d];
		}
		if (mode == CritPartyModeHost) {
			[self sendToEveryone:d];
		}
	}
}

- (void) send:(NSDictionary*)d {
	SCLog(@"Sending: %@", d);
	if (mode == CritPartyModeHost) {
		[self sendToEveryone:d];
	} else {
		[self sendToDataChannel:hostDataChannel data:d];
	}
}

- (void) sendToEveryone:(NSDictionary*)d {
	// Relay to all guests but the originator
	for (NSString* user in guestUsers) {
		if ([user isEqualToString:d[@"from"]]) continue;
		[self sendToGuest:user data:d];
	}
}

- (void) sendTabToUser:(NSString*)username {
	NSDictionary* state = [self editViewInformation];
	NSLog(@"Sending tab: %@", state);
	[self sendToGuest:username data:state];
}

- (void) setupTab:(NSDictionary*)d {
	pauseNotifications = true;

	GSDocument* currentDocument = [(GSApplication *)[NSApplication sharedApplication] currentFontDocument];
	NSWindowController<GSWindowControllerProtocol> *windowController = [currentDocument windowController];
	NSViewController<GSGlyphEditViewControllerProtocol>* evc =
		windowController.activeEditViewController;
	NSMutableAttributedString* string = [[NSMutableAttributedString alloc] init];
	NSLog(@"Got tab: %@", d);

	NSInteger selected = -1;
	unsigned long activeIndex = [d[@"activeIndex"] unsignedLongValue];
	NSInteger selectedLen = 0;
	NSInteger i = 0;
	for (NSDictionary* l in d[@"layers"]) {
		NSAttributedString *A;
		NSDictionary *attributes = nil;
		if ([l[@"layerId"] length] > 0) {
			attributes = @{@"GSLayerIdAttrib" : l[@"layerId"]};
		}
		A = [[NSAttributedString alloc] initWithString:l[@"char"] attributes:attributes];
		[string appendAttributedString:A];
		if([l[@"selected"] boolValue]) {
			if (selected == -1) {
				selected = i;
			}
			selectedLen++;
		}
		i++;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		[evc setWritingDirection:[d[@"writingDirection"] intValue]];
		[[evc.graphicView textStorage] setText:string];
		// now grab the layers and find the right one
		NSArray* layers = [evc allLayers];
		NSInteger i = 0;
		NSLog(@"Setting layer range to %li,%li", selected, selectedLen);
		[evc.graphicView setSelectedLayerRange:NSMakeRange(selected, selectedLen)];
		for (GSLayer* l in layers) {
			if (i == activeIndex) {
				[evc.graphicView setActiveLayer:l];
				[evc.graphicView setActiveIndex:i];
			}
			if (i >= selected && i < selected + selectedLen) {
				[self addObserversToLayer:l];
			}
			i++;
		}
		[evc forceRedraw];
		[self addObserversToGraphicView:evc.graphicView];
		self->pauseNotifications = false;
	});

}

- (void) drawForegroundForLayer:(GSLayer*)Layer options:(NSDictionary *)options {
	if (!connected) { return; }
	for (NSString *username in cursors) {
		// NSLog(@"Drawing cursor %@", cursors[username]);

		NSPoint pt = [cursors[username][@"location"] pointValue];
		NSBezierPath *c = [self arrowCursorPath];
		CGFloat currentZoom = [[self editViewController].graphicView scale];
		NSAffineTransform *transform = [NSAffineTransform transform];
		[transform translateXBy: pt.x yBy: pt.y];
		[c transformUsingAffineTransform:transform];
		[cursors[username][@"color"] setFill];

		[username drawAtPoint:NSMakePoint(pt.x, pt.y - 2 * c.bounds.size.height) withAttributes:@{
		         NSFontAttributeName: [NSFont labelFontOfSize:12 / currentZoom],
		         NSForegroundColorAttributeName:cursors[username][@"color"]
		}];
		[c fill];

	}
}

- (void)setCursor:(NSDictionary*)d {
	NSString* username = d[@"from"];
	NSPoint pt = NSMakePoint([d[@"x"] floatValue], [d[@"y"] floatValue]);
	if (!cursors[username]) {
		cursors[username] = [[NSMutableDictionary alloc] init];
		cursors[username][@"color"] = [self getNewCursorColor];
	}
	cursors[username][@"location"] = [NSValue valueWithPoint:pt];
//    NSLog(@"Setting cursor %@", cursors[username]);
	dispatch_async(dispatch_get_main_queue(), ^{
		[[self editViewController] redraw];
	});
}

/// MARK: - Critparty event callbacks

- (void) mouseMoved:(NSNotification*)notification {
	if (!connected) { return; }
	NSEvent* event = [notification object];
	if (![event isKindOfClass:[NSEvent class]]) { return; }
	NSPoint Loc = [[self editViewController].graphicView getActiveLocation: event];

	[self send:@{
	         @"from": myusername,
	         @"type": @"cursor",
	         @"x": [NSNumber numberWithFloat: Loc.x ],
	         @"y": [NSNumber numberWithFloat: Loc.y ]
	}];
}

- (void)handleConnectionError:(NSString*)error {
	NSLog(@"Got error %@", error);
	dispatch_async(dispatch_get_main_queue(), ^{
		[self->textbox setString:error];
	});
	[self doDisconnect];
}

/// MARK: - Host peer-to-peer administration

- (RTCPeerConnection*)createPeerConnection {
	RTC_OBJC_TYPE(RTCMediaConstraints) * constraints = [self defaultPeerConnectionConstraints];
	RTC_OBJC_TYPE(RTCConfiguration) * config = [[RTC_OBJC_TYPE(RTCConfiguration) alloc] init];
	RTC_OBJC_TYPE(RTCCertificate) * pcert = [RTC_OBJC_TYPE(RTCCertificate)
											 generateCertificateWithParams:@{@"expires" : @100000, @"name" : @"RSASSA-PKCS1-v1_5"}];
	RTC_OBJC_TYPE(RTCIceServer) * server1 =
	[[RTC_OBJC_TYPE(RTCIceServer) alloc] initWithURLStrings:@[ stunServer ]];
	RTC_OBJC_TYPE(RTCIceServer) * server2 =
	[[RTC_OBJC_TYPE(RTCIceServer) alloc] initWithURLStrings:@[ turnServer ]
												   username:@"critparty"
												 credential:@"critparty"];
	config.sdpSemantics = RTCSdpSemanticsUnifiedPlan;
	config.iceServers = @[ server2 ];
	config.certificate = pcert;
	
	RTCPeerConnection* pc = [_factory peerConnectionWithConfiguration:config
														  constraints:constraints
															 delegate:self];
	return pc;
}

- (RTCDataChannel*)createDataChannel:(RTCPeerConnection*)pc {
	RTCDataChannelConfiguration* tt = [[RTCDataChannelConfiguration alloc] init];
	tt.maxRetransmits = 30;
	tt.isOrdered = true;
	tt.isNegotiated = false;
	[tt setChannelId:12];
	RTCDataChannel* dc = [pc dataChannelForLabel:@"glyphs" configuration:tt];
	[dc setDelegate:self];
	SCLog(@"Created data channel %@", [dc description]);
	return dc;
}

- (NSString*)getPeerIdFor:(RTCPeerConnection*)pc {
	__block NSString* answer;
	[guestUsers enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL* stop) {
	         RTCPeerConnection* candidatePc = ((NSDictionary*)value)[@"peerConnection"];
	         if (pc == candidatePc) {
			 answer = ((NSDictionary*)value)[@"peerId"];
		 }
	 }];
	if (!answer) {
		SCLog(@"XXX No peer token found for peer connection?");
	}
	return answer;
}

- (RTCPeerConnection*)getPeerConnectionFor:(NSString*)peerId {
	__block RTC_OBJC_TYPE(RTCPeerConnection) * answer;
	[guestUsers enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL* stop) {
	         RTCPeerConnection* candidatePt = ((NSDictionary*)value)[@"peerId"];
	         if ([peerId isEqualTo:candidatePt]) {
			 answer = ((NSDictionary*)value)[@"peerConnection"];
		 }
	 }];
	if (!answer) {
		SCLog(@"XXX No peer connection found for peer token?");
	}
	return answer;
}

- (NSString*)getUsernameFor:(RTCDataChannel*)dataChannel {
	__block NSString* answer;
	[guestUsers enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL* stop) {
	         RTCDataChannel* candidateDc = ((NSDictionary*)value)[@"dataChannel"];
	         if (candidateDc == dataChannel) {
			 answer = (NSString*)key;
		 }
	 }];
	if (!answer) {
		SCLog(@"XXX No username found for data channel?");
	}
	return answer;
}

- (void)sendToGuest:(NSString*)username data:(NSDictionary*)d {
	if (!guestUsers[username]) return;
	RTCDataChannel* dc = (RTCDataChannel*)guestUsers[username][@"dataChannel"];
	[self sendToDataChannel:dc data:d];
}

/// MARK: - Guest administration


- (void)makeOfferWithCompletion:(void (^)(RTCSessionDescription *))completionHandler {
	hostPeerConnection = [self createPeerConnection];
	hostDataChannel = [self createDataChannel:hostPeerConnection];
	__weak CritParty *weakSelf = self;
	[hostPeerConnection
	 offerForConstraints:[self defaultOfferConstraints]
	 completionHandler:^(RTC_OBJC_TYPE (RTCSessionDescription) * offer, NSError * error) {
	         SCLog(@"Offer created.");
	         CritParty *strongSelf = weakSelf;
	         [strongSelf peerConnection:strongSelf->hostPeerConnection
	          didCreateSessionDescription:offer
	          error:error];
	         completionHandler(offer);
	 }
	];
}

/// MARK: - Signalling client callbacks (common)

- (void)signalingClientChannelDidOpen:(nonnull SignalingClient *)client {
	SCLog(@"Connection to signalling server opened");
}

- (void)signalingClient:(nonnull SignalingClient *)client gotError:(nonnull NSString *)error {
	[self handleConnectionError:error];
}

/// MARK: - Signalling client callbacks (host)

- (void)signalingClient:(nonnull SignalingClient *)client userJoined:(nonnull NSString *)username offer:(nonnull RTCSessionDescription *)offer peerId:(nonnull NSString *)peerId {
	// We are host
	SCLog(@"Got an offer; peer: %@ offer: %@", peerId, offer);
	__weak CritParty *weakSelf = self;
	// Create a new peer connection for this client
	RTCPeerConnection *pc = [self createPeerConnection];
	RTCDataChannel *dc = [self createDataChannel:pc];

	// File it away
	guestUsers[username] = @{
	        @"peerConnection": pc,
	        @"peerId": peerId,
	        @"dataChannel": dc
	};
	__weak RTCPeerConnection *weakPc = pc;
	[pc setRemoteDescription:offer
	 completionHandler:^(NSError *error) {
	         [weakSelf peerConnection:weakPc
	          didSetSessionDescriptionWithError:error];
	 }];
}

- (void)signalingClient:(SignalingClient *)client didReturnSessionID:(NSString *)sessionid {
	hostSessionID.stringValue = sessionid;
}

- (void)signalingClient:(nonnull SignalingClient *)client didReceiveIceCandidate:(nonnull RTCIceCandidate *)icecandidate fromPeer:(nonnull NSString *)peerId {
	SCLog(@"Adding ICE candidate %@", icecandidate);
	SCLog(@"Candidate = %@", [icecandidate JSONDictionary]);
	NSParameterAssert(icecandidate.sdp.length);
	RTCPeerConnection* pc;
	pc = [self getPeerConnectionFor:peerId];
	NSAssert(pc, @"Got  peer connection");
	[pc addIceCandidate:icecandidate];
}

- (void)signalingClient:(nonnull SignalingClient *)client guestExited:(nonnull NSString *)username {
	// Tell everyone
	NSString* message = [username stringByAppendingString:@" has left"];
	[self appendMessage:message];
	// Tell others.
	[self sendToEveryone:@{ @"message": message }];

	// Close peer connection.
	NSDictionary* stuff = guestUsers[username];
	if (!stuff) { return; }
	[(RTCDataChannel*)stuff[@"dataChannel"] close];
	[(RTCPeerConnection*)stuff[@"peerConnection"] close];
}

/// MARK: - Signalling client callbacks (guest)

- (void)signalingClient:(nonnull SignalingClient *)client didReceiveIceCandidate:(nonnull RTCIceCandidate *)icecandidate {
	SCLog(@"Adding ICE candidate %@", icecandidate);
	[guestIceCandidateQueue addObject:icecandidate];
	[self tryToDrainIceCandidateQueue];
}

- (void)signalingClient:(nonnull SignalingClient *)client gotAnswerFromHost:(nonnull RTCSessionDescription *)answer {
	SCLog(@"Got answer from host");
	__weak CritParty *weakSelf = self;
	__weak RTC_OBJC_TYPE(RTCPeerConnection) * weakPc = hostPeerConnection;
	[hostPeerConnection setRemoteDescription:answer
	 completionHandler:^(NSError *error) {
	         [weakSelf peerConnection:weakPc
	          didSetSessionDescriptionWithError:error];
	         [weakSelf tryToDrainIceCandidateQueue];
	 }];
}

- (void)tryToDrainIceCandidateQueue {
	if (![hostPeerConnection remoteDescription]) { return; }
	for (RTCIceCandidate* c in guestIceCandidateQueue) {
		[hostPeerConnection addIceCandidate:c];
	}
	[guestIceCandidateQueue removeAllObjects];
}

- (void)signalingClientShutdown:(nonnull SignalingClient *)client {
	if (hostDataChannel) {
		[hostDataChannel close];
	}
	if (hostPeerConnection) {
		[hostPeerConnection close];
	}
	[self.client disconnect];
	// Send alert
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:@"Host closed connection"];
	[alert setInformativeText:@"Party's over, folks."];
	[alert addButtonWithTitle:@"Ok"];
	[alert runModal];
	[self unlockInterface];
}

/// MARK: - RTC administration (common)

- (RTC_OBJC_TYPE(RTCMediaConstraints) *)defaultAnswerConstraints {
	return [self defaultOfferConstraints];
}

- (RTC_OBJC_TYPE(RTCMediaConstraints) *)defaultOfferConstraints {
	NSDictionary *mandatoryConstraints = @{
	        @"OfferToReceiveAudio" : @"false",
	        @"OfferToReceiveVideo" : @"false",
	};
	RTC_OBJC_TYPE(RTCMediaConstraints) * constraints =
		[[RTC_OBJC_TYPE(RTCMediaConstraints) alloc] initWithMandatoryConstraints:mandatoryConstraints
		 optionalConstraints:nil];
	return constraints;
}

- (RTC_OBJC_TYPE(RTCMediaConstraints) *)defaultPeerConnectionConstraints {
	NSDictionary *optionalConstraints = @{
	        @"DtlsSrtpKeyAgreement" : @"true"
	};
	RTC_OBJC_TYPE(RTCMediaConstraints) * constraints =
		[[RTC_OBJC_TYPE(RTCMediaConstraints) alloc] initWithMandatoryConstraints:nil
		 optionalConstraints:optionalConstraints];
	return constraints;
}

- (void)sendToDataChannel:(RTCDataChannel*)dc data:(NSDictionary*)d {
	NSData* json = [NSJSONSerialization dataWithJSONObject:d
	                options:NSJSONWritingPrettyPrinted
	                error:nil];
	RTCDataBuffer* db = [[RTC_OBJC_TYPE(RTCDataBuffer) alloc]initWithData:json isBinary:false];
	// Set up a queue if we don't have one
	while (dc.channelId >= [outgoingQueue count]) {
		[outgoingQueue addObject:[[NSMutableArray alloc] init]];
	}
	[outgoingQueue[dc.channelId] addObject:db];
	[self tryToDrainMessageQueue:dc];
}

/// MARK: - RTC delegates (common)

- (void)peerConnection:(nonnull RTCPeerConnection *)peerConnection didAddStream:(nonnull RTCMediaStream *)stream {
	SCLog(@"Stream added");
}

- (void)peerConnection:(nonnull RTCPeerConnection *)peerConnection didChangeIceConnectionState:(RTCIceConnectionState)newState {
	SCLog(@"ICE connection changed  %li", (long)newState);
}

- (void)peerConnection:(nonnull RTCPeerConnection *)peerConnection didChangeIceGatheringState:(RTCIceGatheringState)newState {
	SCLog(@"ICE gathering state changed %li", (long)newState);
	if (newState == RTCIceGatheringStateComplete && peerConnection != hostPeerConnection) {
		// Find this PC in answer queue and send.
		NSDictionary* entry = answerQueue[[peerConnection description]];
		if (!entry) {
			return; // Don't know who *that* was
		}
		RTCSessionDescription* sdp = entry[@"answer"];
		NSString *peerId = entry[@"peerId"];
		[(SignalingClientHost*)(self.client) sendAnswer:sdp withPeerId: peerId];
		[answerQueue removeObjectForKey:[peerConnection description]];
	}
	SCLog(@"PC connection state %li", (long)peerConnection.connectionState);

}

- (void)peerConnection:(nonnull RTCPeerConnection *)peerConnection didChangeSignalingState:(RTCSignalingState)stateChanged {
	SCLog(@"Signaling state changed");
}

- (void)peerConnection:(nonnull RTCPeerConnection *)peerConnection didGenerateIceCandidate:(nonnull RTCIceCandidate *)candidate {
	SCLog(@"generated ICE candidate");
	// Work out who it's for.
	NSString *peerId;
	if (peerConnection == hostPeerConnection) {
		assert([self.client isKindOfClass:[SignalingClientGuest class]]);
		[(SignalingClientGuest*)self.client sendIceCandidate: candidate];
	} else {
		assert([self.client isKindOfClass:[SignalingClientHost class]]);
		peerId = [self getPeerIdFor:peerConnection];
		[(SignalingClientHost*)self.client sendIceCandidate: candidate withPeerId: peerId];
	}
}

- (void)peerConnection:(nonnull RTCPeerConnection *)peerConnection didOpenDataChannel:(nonnull RTCDataChannel *)dataChannel {
	SCLog(@"opened data channel");
	if (hostPeerConnection) {
		hostDataChannel = dataChannel;
	}
	dataChannel.delegate = self;
}

- (void)peerConnection:(nonnull RTCPeerConnection *)peerConnection didRemoveIceCandidates:(nonnull NSArray<RTCIceCandidate *> *)candidates {
	SCLog(@"removed ice candidates");
}

- (void)peerConnection:(nonnull RTCPeerConnection *)peerConnection didRemoveStream:(nonnull RTCMediaStream *)stream {
	SCLog(@"stream removed");
}

- (void)peerConnectionShouldNegotiate:(nonnull RTCPeerConnection *)peerConnection {
	SCLog(@"should negotiate");
}

- (void)peerConnection:(RTC_OBJC_TYPE(RTCPeerConnection) *)peerConnection
        didSetSessionDescriptionWithError:(NSError *)error {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (error) {
			[self handleConnectionError:@"Failed to set session description."];
			return;
		}
		// If we're answering and we've just set the remote offer we need to create
		// an answer and set the local description.
		if (!peerConnection.localDescription) {
			SCLog(@"Setting local description");
			RTC_OBJC_TYPE(RTCMediaConstraints) * constraints = [self defaultAnswerConstraints];
			__weak CritParty *weakSelf = self;
			[peerConnection
			 answerForConstraints:constraints
			 completionHandler:^(RTC_OBJC_TYPE (RTCSessionDescription) * sdp, NSError * error) {
			         CritParty *strongSelf = weakSelf;
			         [strongSelf peerConnection:peerConnection
			          didCreateSessionDescription:sdp
			          error:error];
			 }];
		}
	});
}

- (void)peerConnection:(RTC_OBJC_TYPE(RTCPeerConnection) *)peerConnection
        didCreateSessionDescription:(RTC_OBJC_TYPE(RTCSessionDescription) *)sdp
        error:(NSError *)error {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (error) {
			[self handleConnectionError:[error description]];
			return;
		}
		SCLog(@"didCreateSessionDescription");
		__weak CritParty *weakSelf = self;
		__weak RTC_OBJC_TYPE(RTCPeerConnection) * weakPc = peerConnection;
		[peerConnection setLocalDescription:sdp
		 completionHandler:^(NSError *error) {
		         CritParty *strongSelf = weakSelf;
		         [strongSelf peerConnection:weakPc
		          didSetSessionDescriptionWithError:error];
		 }];
		if (sdp.type == RTCSdpTypeAnswer) {
			// Work out where it's going
			NSString* peerId = [self getPeerIdFor: peerConnection];
			if (peerId) {
				self->answerQueue[[peerConnection description]] = @{                    @"answer": sdp, @"peerId": peerId};
				assert(peerConnection.remoteDescription && peerConnection.localDescription);

			} else {
				[self handleConnectionError:@"Can't work out how to answer a join request"];
				return;
			}
		} else {
			assert([self.client isKindOfClass:[SignalingClientGuest class]]);
			// It's my offer. Don't worry about it.
		}
	});
}

/// MARK: - Data channel delegates (common)

- (void)dataChannel:(nonnull RTC_OBJC_TYPE(RTCDataChannel) *)dataChannel didReceiveMessageWithBuffer:(nonnull RTC_OBJC_TYPE(RTCDataBuffer) *)buffer {
	NSDictionary *d = [NSJSONSerialization JSONObjectWithData:[buffer data] options:0 error: nil];
	[self gotMessage:d];
}

- (void)dataChannelDidChangeState:(nonnull RTC_OBJC_TYPE(RTCDataChannel) *)dataChannel {
	SCLog(@"Channel changed state %li", (long)dataChannel.readyState);
	SCLog(@"%@", [dataChannel description]);
	if (dataChannel.readyState == RTCDataChannelStateOpen) {
		dataChannel.delegate = self;
		if (mode == CritPartyModeHost) {
			[self newConnectionEstablishedForUser:[self getUsernameFor:dataChannel]];
		} else {
			[self lockInterface];
		}
	}
}

- (void)dataChannel:(nonnull RTC_OBJC_TYPE(RTCDataChannel) *)dataChannel didChangeBufferedAmount:(uint64_t)amount {
//    SCLog(@"Channel changed buffered amount %llu", amount);
	// Send another message from outgoing queue.
	[self tryToDrainMessageQueue:dataChannel];
}

- (void)tryToDrainMessageQueue:(nonnull RTC_OBJC_TYPE(RTCDataChannel) *)dataChannel {
	if (dataChannel.channelId >= [outgoingQueue count]) return;
	NSMutableArray* myqueue = outgoingQueue[dataChannel.channelId];
	while (dataChannel.bufferedAmount < 16 * 1024 && [myqueue count] > 0) {
		RTCDataBuffer* buf = myqueue.firstObject;
		[myqueue removeObjectAtIndex:0];
		[dataChannel sendData:buf];
	}
}

- (NSBezierPath*) arrowCursorPath {
	NSBezierPath* path = [[NSBezierPath alloc]init];
	[path moveToPoint:NSMakePoint(0,0)];
	[path lineToPoint:NSMakePoint(0,-47)];
	[path lineToPoint:NSMakePoint(11,-35)];
	[path lineToPoint:NSMakePoint(20,-59)];
	[path lineToPoint:NSMakePoint(28,-57)];
	[path lineToPoint:NSMakePoint(18,-33)];
	[path lineToPoint:NSMakePoint(32,-33)];
	[path lineToPoint:NSMakePoint(32,-33)];
	[path closePath];
	return path;
}

@end
