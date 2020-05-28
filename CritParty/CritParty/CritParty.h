//
//  CritParty.h
//  CritParty
//
//  Created by Simon Cozens on 27/05/2020.
//Copyright © 2020 Simon Cozens. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <GlyphsCore/GSFont.h>
#import <GlyphsCore/GSInstance.h>
#import <GlyphsCore/GSFontMaster.h>
#import <GlyphsCore/GlyphsPluginProtocol.h>
@import WebRTC;
#include "RTCSessionDescription+JSON.h"
#include "RTCIceCandidate+JSON.h"
#import "SignalingClient.h"

typedef NS_ENUM(NSInteger, CritPartyMode) {
    CritPartyModeHost,
    CritPartyModeGuest
};

@interface CritParty : NSObject <GlyphsPlugin, SignalingClientDelegate,
SignalingClientHostDelegate, SignalingClientGuestDelegate,
RTCPeerConnectionDelegate, RTCDataChannelDelegate, NSTabViewDelegate>
 {
     CritPartyMode mode;
     bool connected;
     IBOutlet NSWindow *critPartyWindow;
     
     __weak IBOutlet NSTabView *shareJoinTab;
     // Hosting controls
     __weak IBOutlet NSTextField *hostUsernameField;
     __weak IBOutlet NSTextField *hostPassword;
     __weak IBOutlet NSTextField *hostSessionID;
     __weak IBOutlet NSPopUpButton *hostFilePopup;
     // Guest controls
     __weak IBOutlet NSTextField *guestUsernameField;
     __weak IBOutlet NSSecureTextField *guestPassword;
     __weak IBOutlet NSTextField *guestSessionID;
     
     
    __weak IBOutlet NSButton *connectButton;

     __unsafe_unretained IBOutlet NSTextView *textbox;
 }

@property(nonatomic, strong) RTC_OBJC_TYPE(RTCPeerConnectionFactory) * factory;
@property(nonatomic, strong) SignalingClient* client;

@end
