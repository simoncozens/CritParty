//
//  CritParty+FontTransfer.h
//  CritParty
//
//  Created by Simon Cozens on 29/05/2020.
//  Copyright © 2020 Simon Cozens. All rights reserved.
//

#import <AppKit/AppKit.h>


#import "CritParty.h"

NS_ASSUME_NONNULL_BEGIN

@interface CritParty (FontTransfer)
- (void)sendFont:(GSFont*)font toUsername:(NSString*)username;
- (void)saveAndOpenGlyphsDocument:(NSData*)data;
- (void)handleIncomingFontChunk:(NSDictionary*)d;
@end

NS_ASSUME_NONNULL_END
