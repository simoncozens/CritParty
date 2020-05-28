//
//  CritParty.m
//  CritParty
//
//  Created by Simon Cozens on 27/05/2020.
//Copyright © 2020 Simon Cozens. All rights reserved.
//

#import "CritParty.h"
#define SCLog(...) NSLog(__VA_ARGS__)

@interface GSApplication : NSApplication
@property (weak, nonatomic, nullable) GSDocument* currentFontDocument;
@end

@interface GSDocument : NSDocument
@property (nonatomic, retain) GSFont* font;
@end

@implementation CritParty {
    NSMutableDictionary* guestUsers;
    NSMutableDictionary* peerIds;
    RTC_OBJC_TYPE(RTCDataChannel)* hostDataChannel;
    RTC_OBJC_TYPE(RTCPeerConnection)* hostPeerConnection;
    NSMutableDictionary* answerQueue;
      RTC_OBJC_TYPE(RTCFileLogger) * _fileLogger;
    NSString* myusername;
}
@synthesize factory = _factory;

- (id) init {
    NSArray *arrayOfStuff;
	self = [super init];
	if (self) {
        NSLog(@"Crit party is initing");
        NSBundle *thisBundle = [NSBundle bundleForClass:[self class]];
        [thisBundle loadNibNamed:@"CritPartyWindow" owner:self topLevelObjects:&arrayOfStuff];
        NSUInteger viewIndex = [arrayOfStuff indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
            return [obj isKindOfClass:[NSWindow class]];
        }];
        critPartyWindow = [arrayOfStuff objectAtIndex:viewIndex];
        [connectButton setTarget:self];
        [connectButton setAction:@selector(connectButton:)];
        _factory = [[RTC_OBJC_TYPE(RTCPeerConnectionFactory) alloc] init];
        guestUsers = [[NSMutableDictionary alloc] init];
        peerIds = [[NSMutableDictionary alloc] init];
        answerQueue = [[NSMutableDictionary alloc] init];
        [shareJoinTab setDelegate:self];
        connected = false;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mouseMoved:) name:@"mouseMovedNotification" object:nil];
        NSLog(@"Crit party init done");
	}
	return self;
}

- (NSUInteger) interfaceVersion {
	// Distinguishes the API verison the plugin was built for. Return 1.
	return 1;
}

- (void) loadPlugin {
	// Set up stuff
    NSLog(@"Crit party loading");
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
    if ([shareJoinTab indexOfTabViewItem:[shareJoinTab selectedTabViewItem]] == 0) {
        [self beginSharing];
    } else {
        mode = CritPartyModeGuest;
        [self joinAsGuest];
    }
}

- (void)lockInterface {
    connected = true;
    [connectButton setTitle:@"Disconnect"];
    [hostUsernameField setEnabled:false];
    [hostPassword setEnabled:false];
    [guestUsernameField setEnabled:false];
    [guestPassword setEnabled:false];
    [guestSessionID setEnabled:false];
}

- (void)unlockInterface {
    connected = false;
    [connectButton setTitle:@"Connect"];
    [hostUsernameField setEnabled:true];
    [hostPassword setEnabled:true];
    [guestUsernameField setEnabled:true];
    [guestPassword setEnabled:true];
    [guestSessionID setEnabled:true];
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
    NSParameterAssert(guestUsers[username]);
    NSString* message = [username stringByAppendingString:@" has joined"];
    [self appendMessage:message];
    // Tell others.
    [self sendToEveryone:@{ @"message": message }];
    
    // Send the glyphs file down their channel
    GSDocument* doc = [(GSApplication *)[NSApplication sharedApplication] currentFontDocument];
    // Really this ought to be one chosen in the menu.
    if ([doc isKindOfClass:NSClassFromString(@"GSDocument")]) {
        // XXX The following line crashes.
//        NSData *data = [doc dataOfType:@"com.schriftgestaltung.glyphs" error:nil];
        /*
        NSDictionary *message = @{
            @"type": @"glyphsfile",
            @"owner": myusername,
            @"data": [data base64EncodedStringWithOptions:0]
        };
        [self sendToGuest:username data:message];
         */
    }
}

- (void) gotMessage:(NSDictionary*)d {
    SCLog(@"Got message on data channel");
    if (d[@"message"]) {
        NSString* msg;
        if (d[@"from"]) {
            msg = [NSString stringWithFormat:@"%@: %@", d[@"from"], d[@"message"]];
        } else {
            msg = d[@"message"];
        }
        [self appendMessage:msg];
        if (mode == CritPartyModeHost) {
            if ([d[@"from"] isEqualToString:myusername]) { return; }
            [self sendToEveryone:d];
        }
    } else if (d[@"type"] && [d[@"type"] isEqualToString:@"glyphsfile"]) {
        NSData* doc = [[NSData alloc] initWithBase64EncodedString:d[@"data"] options:0];
        // XXX Something something readFromData:doc ofType:@"com.schriftgestaltung.glyphs" error:handler
    }
}

- (void) send:(NSDictionary*)d {
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

/// MARK: - Critparty event callbacks

- (void) mouseMoved:(NSEvent*)event {
    if (!connected) { return; }
    NSPoint event_location = event.locationInWindow;
    NSLog(@"Mouse moved: %f, %f", event_location.x, event_location.y);
//    NSPoint local_point = [self convertPoint:event_location fromView:nil];

    [self send:@{
        @"from": myusername,
        @"type": @"mouseMoved",
        @"x": [NSNumber numberWithFloat: event_location.x ],
        @"y": [NSNumber numberWithFloat: event_location.y ]
    }];
}

/// MARK: - Host peer-to-peer administration

- (RTCPeerConnection*)createPeerConnection {
    RTC_OBJC_TYPE(RTCMediaConstraints) *constraints = [self defaultPeerConnectionConstraints];
    RTC_OBJC_TYPE(RTCConfiguration) *config = [[RTC_OBJC_TYPE(RTCConfiguration) alloc] init];
    RTC_OBJC_TYPE(RTCCertificate) *pcert = [RTC_OBJC_TYPE(RTCCertificate)
        generateCertificateWithParams:@{@"expires" : @100000, @"name" : @"RSASSA-PKCS1-v1_5"}];
//    NSArray *urlStrings = @[  ];
//    RTC_OBJC_TYPE(RTCIceServer) *server =
//        [[RTC_OBJC_TYPE(RTCIceServer) alloc] initWithURLStrings:urlStrings];    config.sdpSemantics = RTCSdpSemanticsUnifiedPlan;
//    config.iceServers = @[ server ];
        config.iceServers = @[ ];
    config.certificate = pcert;

    RTCPeerConnection* pc = [_factory peerConnectionWithConfiguration:config
                                                    constraints:constraints
                                                       delegate:self];
    return pc;
}

- (RTCDataChannel*)createDataChannel:(RTCPeerConnection*)pc {
    RTCDataChannelConfiguration* tt = [[RTCDataChannelConfiguration alloc] init];
    tt.maxRetransmits = 30;
    tt.isOrdered = false;
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
    __block RTC_OBJC_TYPE(RTCPeerConnection)* answer;
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


- (void)makeOfferWithCompletion:(void(^)(RTCSessionDescription *))completionHandler {
    hostPeerConnection = [self createPeerConnection];
    hostDataChannel = [self createDataChannel:hostPeerConnection];
    __weak CritParty *weakSelf = self;
    [hostPeerConnection
        offerForConstraints:[self defaultOfferConstraints]
          completionHandler:^(RTC_OBJC_TYPE(RTCSessionDescription) * offer, NSError * error) {
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
    NSLog(@"Got error %@", error);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->textbox setString:error];
        self->connected = false;
        [self unlockInterface];
    });
}



- (void)signalingClient:(nonnull SignalingClient *)client didGetStats:(nonnull NSArray *)stats {
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


/// MARK: - Signalling client callbacks (guest)

- (void)signalingClient:(nonnull SignalingClient *)client didReceiveIceCandidate:(nonnull RTCIceCandidate *)icecandidate {
    SCLog(@"Adding ICE candidate %@", icecandidate);
    [hostPeerConnection addIceCandidate:icecandidate];
}


- (void)signalingClient:(nonnull SignalingClient *)client gotAnswerFromHost:(nonnull RTCSessionDescription *)answer {
    SCLog(@"Got answer from host");
    __weak CritParty *weakSelf = self;
    __weak RTC_OBJC_TYPE(RTCPeerConnection) *weakPc = hostPeerConnection;
    [hostPeerConnection setRemoteDescription:answer
                           completionHandler:^(NSError *error) {
        [weakSelf peerConnection:weakPc
didSetSessionDescriptionWithError:error];
    }];

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
    RTC_OBJC_TYPE(RTCMediaConstraints) *constraints =
    [[RTC_OBJC_TYPE(RTCMediaConstraints) alloc] initWithMandatoryConstraints:mandatoryConstraints
                                                         optionalConstraints:nil];
    return constraints;
}

- (RTC_OBJC_TYPE(RTCMediaConstraints) *)defaultPeerConnectionConstraints {
    NSDictionary *optionalConstraints = @{
        @"DtlsSrtpKeyAgreement" : @"true"
    };
    RTC_OBJC_TYPE(RTCMediaConstraints) *constraints =
    [[RTC_OBJC_TYPE(RTCMediaConstraints) alloc] initWithMandatoryConstraints:nil
                                                         optionalConstraints:optionalConstraints];
    return constraints;
}

- (void)sendToDataChannel:(RTCDataChannel*)dc data:(NSDictionary*)d {
    NSData* json = [NSJSONSerialization dataWithJSONObject:d
                                        options:NSJSONWritingPrettyPrinted
                                          error:nil];
    RTCDataBuffer* db = [[RTC_OBJC_TYPE(RTCDataBuffer) alloc]initWithData:json isBinary:false];
    [dc sendData:db];
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
        NSAssert(entry, @"Have answer for this peer");
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
    dataChannel.delegate=self;
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
            RTCLogError(@"Failed to set session description. Error: %@", error);
            //      [self disconnect];
            return;
        }
        // If we're answering and we've just set the remote offer we need to create
        // an answer and set the local description.
        if (!peerConnection.localDescription) {
            SCLog(@"Setting local description");
            RTC_OBJC_TYPE(RTCMediaConstraints) *constraints = [self defaultAnswerConstraints];
            __weak CritParty *weakSelf = self;
            [peerConnection
             answerForConstraints:constraints
             completionHandler:^(RTC_OBJC_TYPE(RTCSessionDescription) * sdp, NSError * error) {
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
            RTCLogError(@"Failed to create session description. Error: %@", error);
            //      [self disconnect];
            return;
        }
        SCLog(@"didCreateSessionDescription");
        __weak CritParty *weakSelf = self;
        __weak RTC_OBJC_TYPE(RTCPeerConnection)* weakPc = peerConnection;
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
                NSAssert(false, @"Couldn't find where to send answer");
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
        }
    }
}
- (void)dataChannel:(nonnull RTC_OBJC_TYPE(RTCDataChannel) *)dataChannel didChangeBufferedAmount:(uint64_t)amount {
    SCLog(@"Channel changed buffered amount %llu", amount);
}
@end