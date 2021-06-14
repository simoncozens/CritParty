//
//  CritParty+Observers.h
//  CritParty
//
//  Created by Simon Cozens on 29/05/2020.
//  Copyright © 2020 Simon Cozens. All rights reserved.
//

#import <AppKit/AppKit.h>


#import "CritParty.h"

NS_ASSUME_NONNULL_BEGIN

@interface CritParty (Observers)
-(void)addObserversToEditViewController:(NSViewController<GSGlyphEditViewControllerProtocol> *)editViewController;
-(void)addObserversToGraphicView:(NSView<GSGlyphEditViewProtocol>*)graphicView;
-(void)addObserversToLayer:(GSLayer*)l;
-(void)updateLayer:(NSDictionary*)d;
- (NSDictionary*)editViewInformation;
@end

NS_ASSUME_NONNULL_END
