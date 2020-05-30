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
-(void) addObserversToGraphicView:(NSView<GSGlyphEditViewProtocol, NSTextInputClient>*)graphicView;
-(void) addObserversToLayer:(GSLayer*)l;
-(void) addObserversToPath:(GSPath*)p;
-(void) addObserversToNode:(GSNode*)n;
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context;
-(void) sendUpdatedNode:(GSNode*)n;
-(void) updatePath:(NSDictionary*)d;
-(void) updateNode:(NSDictionary*)d;
-(void) updateAnchor:(NSDictionary*)d;
-(void) updateLayer:(NSDictionary*)d;
- (NSDictionary*)editViewInformation;
@end

NS_ASSUME_NONNULL_END
