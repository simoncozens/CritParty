//
//  AppDelegate.m
//  CritPartyDummyClient
//
//  Created by Simon Cozens on 22/05/2020.
//  Copyright © 2020 Simon Cozens. All rights reserved.
//

#import "AppDelegate.h"
#include "RTCSessionDescription+JSON.h"
#include "RTCIceCandidate+JSON.h"

@interface AppDelegate () <NSWindowDelegate, SignalingClientDelegate,
SignalingClientHostDelegate, SignalingClientGuestDelegate,
RTCPeerConnectionDelegate, RTCDataChannelDelegate>

typedef NS_ENUM(NSInteger, AppMode) {
ModeHost,
    ModeGuest
};
    
#define SCLog(...) NSLog(__VA_ARGS__)

@property (weak) IBOutlet NSTextField *sessionID;
@property (weak) IBOutlet NSButton *beepButton;
@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTextField *usernameField;
@property (unsafe_unretained) IBOutlet NSTextView *textbox;

@end

@implementation AppDelegate {
    NSMutableDictionary* guestUsers;
    NSMutableDictionary* peerIds;
    RTC_OBJC_TYPE(RTCDataChannel)* hostDataChannel;
    RTC_OBJC_TYPE(RTCPeerConnection)* hostPeerConnection;
    AppMode mode;
    NSMutableDictionary* answerQueue;
      RTC_OBJC_TYPE(RTCFileLogger) * _fileLogger;
}
@synthesize factory = _factory;
@synthesize client = _client;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    _window.delegate = self;
    [_beepButton setEnabled:false];
    _factory = [[RTC_OBJC_TYPE(RTCPeerConnectionFactory) alloc] init];
    guestUsers = [[NSMutableDictionary alloc] init];
    peerIds = [[NSMutableDictionary alloc] init];
    answerQueue = [[NSMutableDictionary alloc] init];
    _fileLogger = [[RTC_OBJC_TYPE(RTCFileLogger) alloc] init];
    [_fileLogger setSeverity:RTCFileLoggerSeverityVerbose];
    [_fileLogger start];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (IBAction)connectButton:(id)sender {
    SCLog(@"Session ID: %i", _sessionID.intValue);
    if (! _sessionID.intValue) {
        _client = [[SignalingClientHost alloc] initWithDelegate:self username:[_usernameField stringValue] password:@"abcdefg"];
    } else {
        NSString* sid = _sessionID.stringValue;
        [self makeOfferWithCompletion:^void (RTCSessionDescription* offer) {
            self->_client = [[SignalingClientGuest alloc] initWithDelegate:self username:[self->_usernameField stringValue] password:@"abcdefg" sessionid:sid offer:offer];
        }];
    }
}
- (IBAction)beep:(id)sender {
    NSDictionary* message = @{
        @"from": _client.username,
        @"message": @"beep"
    };
    if (hostDataChannel) {
        [self sendToDataChannel:hostDataChannel data:message];
    } else {
        for (NSString* user in guestUsers) {
            [self sendToDataChannel:(RTCDataChannel*)guestUsers[user][@"dataChannel"] data:message];
        }
    }
}

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

/// MARK: - Host administration

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

/// MARK: - Guest administration


- (void)makeOfferWithCompletion:(void(^)(RTCSessionDescription *))completionHandler {
    hostPeerConnection = [self createPeerConnection];
    hostDataChannel = [self createDataChannel:hostPeerConnection];
    __weak AppDelegate *weakSelf = self;
    [hostPeerConnection
        offerForConstraints:[self defaultOfferConstraints]
          completionHandler:^(RTC_OBJC_TYPE(RTCSessionDescription) * offer, NSError * error) {
            SCLog(@"Offer created.");
            AppDelegate *strongSelf = weakSelf;
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
        [self.textbox setString:error];
    });
}



- (void)signalingClient:(nonnull SignalingClient *)client didGetStats:(nonnull NSArray *)stats {
}

/// MARK: - Signalling client callbacks (host)

- (void)signalingClient:(nonnull SignalingClient *)client userJoined:(nonnull NSString *)username offer:(nonnull RTCSessionDescription *)offer peerId:(nonnull NSString *)peerId {
    // We are host
    SCLog(@"Got an offer; peer: %@ offer: %@", peerId, offer);
    __weak AppDelegate *weakSelf = self;
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
    _sessionID.stringValue = sessionid;
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
    __weak AppDelegate *weakSelf = self;
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
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.beepButton setEnabled:true];
    });
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
            __weak AppDelegate *weakSelf = self;
            [peerConnection
             answerForConstraints:constraints
             completionHandler:^(RTC_OBJC_TYPE(RTCSessionDescription) * sdp, NSError * error) {
                AppDelegate *strongSelf = weakSelf;
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
        __weak AppDelegate *weakSelf = self;
        __weak RTC_OBJC_TYPE(RTCPeerConnection)* weakPc = peerConnection;
        [peerConnection setLocalDescription:sdp
                          completionHandler:^(NSError *error) {
            AppDelegate *strongSelf = weakSelf;
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
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.textbox setString:[[self.textbox string] stringByAppendingFormat:@"\n%@: %@",d[@"from"], d[@"message"]]];
     });
    SCLog(@"Got message on data channel");
    if (!hostPeerConnection) {
        // Relay to all guests but the originator
        for (NSString* user in guestUsers) {
            if ([user isEqualToString:d[@"from"]]) continue;
                        [self sendToDataChannel:(RTCDataChannel*)guestUsers[user][@"dataChannel"] data:d];
        }
    }
}

- (void)dataChannelDidChangeState:(nonnull RTC_OBJC_TYPE(RTCDataChannel) *)dataChannel {
    SCLog(@"Channel changed state %li", (long)dataChannel.readyState);
    SCLog(@"%@", [dataChannel description]);
    dataChannel.delegate = self;
}
- (void)dataChannel:(nonnull RTC_OBJC_TYPE(RTCDataChannel) *)dataChannel didChangeBufferedAmount:(uint64_t)amount {
    SCLog(@"Channel changed buffered amount %llu", amount);
}
@end
