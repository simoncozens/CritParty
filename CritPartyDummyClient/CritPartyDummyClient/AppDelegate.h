//
//  AppDelegate.h
//  CritPartyDummyClient
//
//  Created by Simon Cozens on 22/05/2020.
//  Copyright © 2020 Simon Cozens. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SignalingClient.h"
@import WebRTC;
#import "WebRTC/RTCPeerConnection.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) RTC_OBJC_TYPE(RTCPeerConnectionFactory) * factory;
@property(nonatomic, strong) SignalingClient* client;
@end

