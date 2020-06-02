//
//  SignalingClient.m
//  CritPartyDummyClient
//
//  Created by Simon Cozens on 22/05/2020.
//  Copyright © 2020 Simon Cozens. All rights reserved.
//

#import "SignalingClient.h"
#import "SRWebSocket.h"

@interface SignalingClient () <SRWebSocketDelegate>
@end

@implementation SignalingClient {
	@protected SRWebSocket *_socket;
	@protected bool opened;
	NSMutableArray* messageQueue;
}

@synthesize password = _password;
@synthesize username = _username;

NSString *url = @"ws://critparty.corvelsoftware.co.uk:9000/";

- (instancetype)init {
	_socket = [[SRWebSocket alloc] initWithURL:[[NSURL alloc] initWithString:url]];
	_socket.delegate = self;
	messageQueue = [[NSMutableArray alloc] init];
	opened = false;
	[_socket open]; // We can open socket straight away.
	return self;
}

- (void)disconnect {
	[_socket close];
}

- (void)sendMessage:(NSDictionary*)message {
	if (!opened) {
		[messageQueue addObject:message];
		return;
	};
	NSData *messageJSONObject =
		[NSJSONSerialization dataWithJSONObject:message
		 options:NSJSONWritingPrettyPrinted
		 error:nil];
	NSString *messageString =
		[[NSString alloc] initWithData:messageJSONObject
		 encoding:NSUTF8StringEncoding];
	NSLog(@"Sending to ws: %@", messageString);
	[_socket send:messageString];
}

// MARK: - SocketRocket delegate methods

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(id)message {
	NSDictionary *d = [NSJSONSerialization JSONObjectWithData:[(NSString*)message dataUsingEncoding:NSUTF8StringEncoding] options:0 error: nil];
	NSLog(@"Got message %@",d);
	if (d[@"hello"])     { return; }
	if (d[@"sessionid"]) {
		[(SignalingClientHost*)self gotSessionId:d];
		return;
	}
	if (d[@"type"] && [d[@"type"] isEqual:@"newconnection"]) {
		[(SignalingClientHost*)self newConnection:d];
		return;
	}
	if (d[@"type"] && [d[@"type"] isEqual:@"answer"]) {
		[(SignalingClientGuest*)self gotAnswer:d];
		return;
	}
	if (d[@"type"] && [d[@"type"] isEqual:@"ice-candidate"]) {
		[self gotIceCandidate:d];
	}
	if (d[@"type"] && [d[@"type"] isEqual:@"connectionclosed"]) {
		[(SignalingClientHost*)self connectionClosed:d[@"username"]];
	}
	if (d[@"type"] && [d[@"type"] isEqual:@"shutdown"]) {
		[(SignalingClientGuest*)self sessionShutdown];
	}

	if (d[@"error"]) {
		[self gotError:d[@"error"]];
	}

}

- (void)gotIceCandidate:(NSDictionary *)d {
	NSAssert(false, @"Not reached - should call subclass method");
}

- (void)gotError:(NSDictionary *)d {
	NSAssert(false, @"Not reached - should call subclass method");
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error;
{
	NSLog(@":( Websocket Failed With Error %@", error);
	[self gotError:@{@"ok": @"false", @"error": [error description]}];
}

@end

// MARK: - Host implementation

@implementation SignalingClientHost : SignalingClient {
}
@synthesize delegate = _delegate;

- (instancetype)initWithDelegate:(id<SignalingClientDelegate,SignalingClientHostDelegate>)delegate
        username:(nonnull NSString *)username
        password:(nonnull NSString *)password {
	self.delegate = delegate;
	self.username = username;
	self.password = password;
	return [super init];
}

- (void)webSocketDidOpen:(SRWebSocket *)webSocket;
{
	NSAssert(self.username, @"Username exists");
	NSAssert(self.password, @"Password exists");
	NSDictionary* connectstring = @{
	        @"type": @"newsession",
	        @"password": self.password,
	        @"username": self.username,
	};
	opened = true;
	[self sendMessage:connectstring];
}

- (void)newConnection:(NSDictionary*)d {
	NSParameterAssert(d[@"offer"]);
	NSParameterAssert(d[@"username"]);
	NSParameterAssert(d[@"peerid"]);
	NSLog(@"Sending offer %@", d[@"offer"]);
	RTC_OBJC_TYPE(RTCSessionDescription) * description =
		[RTC_OBJC_TYPE(RTCSessionDescription) descriptionFromJSONDictionary:d[@"offer"]];
	NSParameterAssert(description.sdp.length);
	[self.delegate signalingClient:self userJoined:d[@"username"] offer:description peerId:d[@"peerid"]];
}

- (void)gotError:(NSString *)error {
	[self.delegate signalingClient:self gotError:error];
}

- (void)gotSessionId:(NSDictionary *)d {
	[self.delegate signalingClient:self didReturnSessionID:d[@"sessionid"]];
}

- (void)connectionClosed:(NSString *)username {
	[self.delegate signalingClient:self guestExited:username];
}

- (void)gotIceCandidate:(NSDictionary *)d {
	NSParameterAssert(d[@"candidate"]);
	RTCIceCandidate* icecandidate = [RTC_OBJC_TYPE(RTCIceCandidate) candidateFromJSONDictionary:d[@"candidate"]];
	[self.delegate signalingClient:self didReceiveIceCandidate:icecandidate fromPeer:d[@"peerid"]];
}

- (void)sendAnswer:(RTCSessionDescription*)answer withPeerId: (NSString*)peerid {
	NSLog(@"Sending answer back to guest with peer id %@", peerid);
	NSDictionary* message = @{
	        @"type": @"answer",
	        @"peerid": peerid,
	        @"answer": [answer asDictionary]
	};
	[self sendMessage: message];
}

- (void)sendIceCandidate:(RTCIceCandidate*)icecandidate withPeerId:(nonnull NSString *)peerid {
	NSLog(@"Sending ICE candidate back to guest with peer id %@", peerid);
	NSDictionary* message = @{
	        @"type": @"ice-candidate",
	        @"candidate": [icecandidate JSONDictionary],
	        @"peerid": peerid
	};
	[self sendMessage: message];
}

@end

// MARK: - Guest implementation

@implementation SignalingClientGuest : SignalingClient {
}
@synthesize delegate = _delegate;
@synthesize offer = _offer;

- (instancetype)initWithDelegate:(id<SignalingClientDelegate,SignalingClientGuestDelegate>)delegate
        username:(NSString*)username
        password:(nonnull NSString *)password
        sessionid:(nonnull NSString *)sessionid
        offer:(nonnull RTCSessionDescription *)offer {
	_delegate = delegate;
	self.password = password;
	self.username = username;
	self.sessionid = sessionid;
	self.offer = offer;
	return [super init];
}

- (void)webSocketDidOpen:(SRWebSocket *)webSocket;
{
	// We have to create and send an offer
	NSAssert(self.username, @"Username exists");
	NSAssert(self.password, @"Password exists");
	NSAssert(self.offer, @"Offer exists");
	opened = true;
	NSDictionary* connectstring = @{
	        @"type": @"joinsession",
	        @"password": self.password,
	        @"username": self.username,
	        @"sessionid": self.sessionid,
	        @"offer": [self.offer asDictionary]
	};
	[self sendMessage:connectstring];
	// Drain the message queue
	for (NSDictionary* d in messageQueue) {
		[self sendMessage:d];
	}
	[messageQueue removeAllObjects];
}

- (void)gotError:(NSString *)error {
	if ([error isEqualToString:@"You're not in a session!"]) return;
	[self.delegate signalingClient:self gotError:error];
}

- (void)sessionShutdown {
	[self.delegate signalingClientShutdown:self];
}

- (void)gotAnswer:(NSDictionary*)d {
	RTC_OBJC_TYPE(RTCSessionDescription) * description =
		[RTC_OBJC_TYPE(RTCSessionDescription) descriptionFromJSONDictionary:d[@"answer"]];
	[((SignalingClientGuest*)self).delegate signalingClient:self gotAnswerFromHost:description];
}

- (void)gotIceCandidate:(NSDictionary *)d {
	NSParameterAssert(d[@"candidate"]);
	RTCIceCandidate* icecandidate = [RTC_OBJC_TYPE(RTCIceCandidate) candidateFromJSONDictionary:d[@"candidate"]];
	[self.delegate signalingClient:self didReceiveIceCandidate:icecandidate];
}

- (void)sendIceCandidate:(RTCIceCandidate*)candidate {
	NSLog(@"Sending ICE candidate back to host");
	NSDictionary* message = @{
	        @"type": @"ice-candidate",
	        @"candidate": [candidate JSONDictionary]
	};
	[self sendMessage: message];
}

@end

