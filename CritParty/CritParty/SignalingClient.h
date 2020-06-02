//
//  SignalingClient.h
//  CritPartyDummyClient
//
//  Created by Simon Cozens on 22/05/2020.
//  Copyright © 2020 Simon Cozens. All rights reserved.
//

#import <Foundation/Foundation.h>
@import WebRTC;
#include "RTCSessionDescription+JSON.h"
#include "RTCIceCandidate+JSON.h"

NS_ASSUME_NONNULL_BEGIN

@class SignalingClient;
@class SignalingClientHost;
@class SignalingClientGuest;

@protocol SignalingClientDelegate <NSObject>
- (void)signalingClient:(SignalingClient *)client gotError:(NSString *)error;
- (void)signalingClientChannelDidOpen:(SignalingClient *)client;
@end

@protocol SignalingClientHostDelegate <NSObject>
- (void)signalingClient:(SignalingClient *)client didReturnSessionID:(NSString *)sessionid;
- (void)signalingClient:(SignalingClient *)client userJoined:(NSString *)username offer:(RTCSessionDescription*) offer peerId:(NSString*)peerId;
- (void)signalingClient:(SignalingClient *)client didReceiveIceCandidate:(RTCIceCandidate*)candidate fromPeer:(NSString*)peerId;
- (void)signalingClient:(SignalingClient *)client guestExited:(NSString*)username;

@end

@protocol SignalingClientGuestDelegate <NSObject>
- (void)signalingClient:(nonnull SignalingClient *)client gotAnswerFromHost:(nonnull RTCSessionDescription*)answer;
- (void)signalingClient:(SignalingClient *)client didReceiveIceCandidate:(RTCIceCandidate*)data;
- (void)signalingClientShutdown:(SignalingClient*) client;
@end

@interface SignalingClient : NSObject
@property(nonatomic) NSString* sessionid;
@property(nonatomic) NSString* username;
@property(nonatomic) NSString* password;
- (void)gotIceCandidate:(NSDictionary*) d;
- (void)disconnect;
@end

@interface SignalingClientHost : SignalingClient
@property(nonatomic, weak) id<SignalingClientDelegate,SignalingClientHostDelegate> delegate;

- (instancetype)initWithDelegate:(id<SignalingClientDelegate,SignalingClientHostDelegate>)delegate
        username: (NSString*)username
        password: (NSString*)password;

- (void)newConnection:(NSDictionary*)d;
- (void)gotSessionId:(NSDictionary*)d;
- (void)gotError:(NSString*)error;

- (void)sendAnswer:(RTCSessionDescription*)answer withPeerId: (NSString*)peerid;
- (void)sendIceCandidate:(RTCIceCandidate*)candidate withPeerId: (NSString*)peerid;
- (void)connectionClosed:(NSString*)username;
@end

@interface SignalingClientGuest : SignalingClient
@property(nonatomic, weak) id<SignalingClientDelegate,SignalingClientGuestDelegate> delegate;
@property RTCSessionDescription* offer;

- (instancetype)initWithDelegate:(id<SignalingClientDelegate,SignalingClientHostDelegate>)delegate
        username: (NSString*)username
        password: (NSString*)password
        sessionid: (NSString*)sessionid
        offer: (RTCSessionDescription*)offer;

- (void)sendIceCandidate:(RTCIceCandidate*)candidate;
- (void)gotAnswer:(NSDictionary*)d;
- (void)gotError:(NSString*)error;
- (void)sessionShutdown;

@end

NS_ASSUME_NONNULL_END
