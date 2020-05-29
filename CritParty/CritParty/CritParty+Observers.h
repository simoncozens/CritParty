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
-(void) addObserversToLayer:(GSLayer*)l;
-(void) addObserversToPath:(GSPath*)p;
-(void) addObserversToNode:(GSNode*)n;
@end

NS_ASSUME_NONNULL_END
