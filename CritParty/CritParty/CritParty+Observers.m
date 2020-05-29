//
//  CritParty+Observers.m
//  CritParty
//
//  Created by Simon Cozens on 29/05/2020.
//  Copyright © 2020 Simon Cozens. All rights reserved.
//

#import "CritParty+Observers.h"

#import <AppKit/AppKit.h>


@implementation CritParty (Observers)

-(void) addObserversToLayer:(GSLayer*)l {
    [l addObserver:self forKeyPath:@"paths" options:0 context:nil];
    GSPath* p;
    for (p in l.paths) {
        [self addObserversToPath:p];
    }
}

-(void) addObserversToPath:(GSPath*)p {
    NSLog(@"Adding obsrerver to path %@", p);
    [p addObserver:self forKeyPath:@"nodes" options:0 context:nil];
    GSNode *n;
    for (n in p.nodes) {
        [self addObserversToNode:n];
    }
}

-(void) addObserversToNode:(GSNode*)n {
    NSLog(@"Adding obsrerver to node %@", n);
    [n addObserver:self forKeyPath:@"connection" options:0 context:nil];
    [n addObserver:self forKeyPath:@"type" options:0 context:nil];
    [n addObserver:self forKeyPath:@"position" options:0 context:nil];
}



@end
