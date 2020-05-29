//
//  CritParty.h
//  CritParty
//
//  Created by Simon Cozens on 27/05/2020.
//Copyright © 2020 Simon Cozens. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <GlyphsCore/GSFont.h>
#import <GlyphsCore/GSFont+SerialSave.h>
#import <GlyphsCore/GSInstance.h>
#import <GlyphsCore/GSLayer.h>
#import <GlyphsCore/GSPath.h>
#import <GlyphsCore/GSCallbackHandler.h>
#import <GlyphsCore/GSFontMaster.h>
#import <GlyphsCore/GlyphsPluginProtocol.h>
#import <GlyphsCore/GSGeometrieHelper.h>
#import <GlyphsCore/GSWindowControllerProtocol.h>
#import <GlyphsCore/GlyphsToolEventProtocol.h>
#import <GlyphsCore/GSGlyphViewControllerProtocol.h>

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
     NSMutableDictionary* guestUsers;
     NSMutableDictionary* peerIds;
     RTC_OBJC_TYPE(RTCDataChannel)* hostDataChannel;
     RTC_OBJC_TYPE(RTCPeerConnection)* hostPeerConnection;
     NSMutableDictionary* answerQueue;
     NSMutableArray* outgoingQueue;
     RTC_OBJC_TYPE(RTCFileLogger) * _fileLogger;
     NSString* myusername;
     NSMutableDictionary* cursors;
     unsigned int cursorColor;
     bool pauseNotifications;
     NSURL* incomingFontFile;

 }

@property(nonatomic, strong) RTC_OBJC_TYPE(RTCPeerConnectionFactory) * factory;
@property(nonatomic, strong) SignalingClient* client;

-(void) sendUpdatedNode:(GSNode*)n;
-(void) sendToGuest:(NSString*)username data:(NSDictionary*)d;
-(void) handleConnectionError:(NSString*)error;
- (void)appendMessage:(NSString *)message;
@end
