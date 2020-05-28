/*
 *  Copyright 2014 The WebRTC Project Authors. All rights reserved.
 *
 *  Use of this source code is governed by a BSD-style license
 *  that can be found in the LICENSE file in the root of the source
 *  tree. An additional intellectual property rights grant can be found
 *  in the file PATENTS.  All contributing project authors may
 *  be found in the AUTHORS file in the root of the source tree.
 */

#import "RTCSessionDescription+JSON.h"

static NSString const *kRTCSessionDescriptionTypeKey = @"type";
static NSString const *kRTCSessionDescriptionSdpKey = @"sdp";

@implementation RTC_OBJC_TYPE (RTCSessionDescription)
(JSON)

+ (RTCSdpType)myTypeForString:(NSString*)string {
    if ([string isEqualToString:@"offer"]) {
        return RTCSdpTypeOffer;
    } else if ([string isEqualToString:@"pranswer"]) {
        return RTCSdpTypePrAnswer;
  } else if ([string isEqualToString:@"answer"]) {
    return RTCSdpTypeAnswer;
  } else {
      NSAssert(false, @"Not reached");
    return RTCSdpTypeOffer;
  }
}

    + (RTC_OBJC_TYPE(RTCSessionDescription) *)descriptionFromJSONDictionary
    : (NSDictionary *)dictionary {
  NSString *typeString = dictionary[kRTCSessionDescriptionTypeKey];
  RTCSdpType type = [[self class] myTypeForString:typeString];
  NSString *sdp = dictionary[kRTCSessionDescriptionSdpKey];
  return [[RTC_OBJC_TYPE(RTCSessionDescription) alloc] initWithType:type sdp:sdp];
}

- (NSDictionary *)asDictionary {
    NSString *type = [[self class] stringForType:self.type];
    return @{
        kRTCSessionDescriptionTypeKey : type,
        kRTCSessionDescriptionSdpKey : self.sdp
    };
}
    
- (NSData *)JSONData {
  return [NSJSONSerialization dataWithJSONObject:[self asDictionary] options:0 error:nil];
}

@end
