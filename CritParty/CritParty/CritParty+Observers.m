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
    @try {
        [l removeObserver:self forKeyPath:@"paths"];
    } @catch (NSException * __unused exception) {} // Horrible
    [l addObserver:self forKeyPath:@"paths" options:0 context:nil];
    GSPath* p;
    for (p in l.paths) {
        [self addObserversToPath:p];
    }
}

-(void) addObserversToPath:(GSPath*)p {
    NSLog(@"Adding obsrerver to path %@", p);
    @try {
        [p removeObserver:self forKeyPath:@"nodes"];
    } @catch (NSException * __unused exception) {} // Horrible
    [p addObserver:self forKeyPath:@"nodes" options:0 context:nil];
    GSNode *n;
    for (n in p.nodes) {
        [self addObserversToNode:n];
    }
}

-(void) addObserversToNode:(GSNode*)n {
    NSLog(@"Adding obsrerver to node %@", n);
    @try {
        [n removeObserver:self forKeyPath:@"connection"];
        [n removeObserver:self forKeyPath:@"type"];
        [n removeObserver:self forKeyPath:@"position"];
    }@ catch (NSException * __unused exception) {} // Horrible
    [n addObserver:self forKeyPath:@"connection" options:0 context:nil];
    [n addObserver:self forKeyPath:@"type" options:0 context:nil];
    [n addObserver:self forKeyPath:@"position" options:0 context:nil];
}


- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    NSLog(@"Observer: %@ %@ %@", keyPath, object, change);
    if ([object isKindOfClass:[GSNode class]] &&
        ([keyPath isEqualToString:@"position"] ||
         [keyPath isEqualToString:@"connection"] ||
         [keyPath isEqualToString:@"type"])) {
        [self sendUpdatedNode:object];
        return;
    }
    if ([keyPath isEqualToString:@"nodes"]) {
        [self sendUpdatedPath:object];
        return;
    }
    if ([keyPath isEqualToString:@"paths"]) {
        [self sendUpdatedLayer:object];
        return;
    }
}

- (NSDictionary*)nodeAsDictionary:(GSNode*)n {
    GSPath *p = n.parent;
    return @{
        @"from": myusername,
        @"type": @"node",
        @"x": [NSNumber numberWithFloat:n.position.x],
        @"y": [NSNumber numberWithFloat:n.position.y],
        @"connection": [NSNumber numberWithInt:n.connection],
        @"nodetype": [NSNumber numberWithInt:n.type],
        @"index": [NSNumber numberWithUnsignedInteger:[p indexOfNode:n]],
        @"pathindex":[NSNumber numberWithUnsignedInteger:[p.parent indexOfPath: p]]
    };
}

- (NSDictionary*)pathAsDictionary:(GSPath*)p {
    return @{
        @"from": myusername,
        @"type": @"path",
        @"pathindex": [NSNumber numberWithUnsignedInteger:[p.parent indexOfPath: p]],
        @"pathDict": [p pathDict]
    };
}

- (NSDictionary*)layerAsDictionary:(GSLayer*)l {
    NSMutableArray* paths = [[NSMutableArray alloc] init];
    for (GSPath *p in l.paths) { [paths addObject:[self pathAsDictionary:p]];}
    
    return @{
        @"from": myusername,
        @"type": @"layer",
        @"layerid": l.layerId,
        @"layerDict": [l layerDict],
    };
}

- (void) sendUpdatedPath:(GSPath*)p {
    if(!connected || pauseNotifications) return;
    [self send: [self pathAsDictionary:p]];
}

- (void) sendUpdatedLayer:(GSLayer*)l {
    if(!connected || pauseNotifications) return;
    [self send: [self layerAsDictionary:l]];
}

- (void) updatePath:(NSDictionary*)d {
    GSLayer *layer = [self editViewController].activeLayer;
    if(!layer) return;
    NSUInteger pathIndex = [d[@"pathindex"] unsignedIntegerValue];
    pauseNotifications = true;
    [layer removePathAtIndex:pathIndex];
    GSPath *p = [[GSPath alloc] initWithPathDict:d[@"pathDict"]];
    [self addObserversToPath:p];
    [layer insertPath:p atIndex:pathIndex];
    pauseNotifications = false;
    NSLog(@"Constructed a path %@", p);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self editViewController] redraw];
    });
}

- (void) updateLayer:(NSDictionary*)d {
    GSLayer *layer = [self editViewController].activeLayer;
    if(!layer) return;
    GSGlyph *g = layer.parent;
    pauseNotifications = true;
    GSLayer *newLayer = [[GSLayer alloc] initWithLayerDict:d[@"layerDict"]];
    [self addObserversToLayer:newLayer];
    [g setLayer:newLayer forKey:d[@"layerId"]];
    NSLog(@"Constructed a layer %@ (paths %lu)", [newLayer layerDict], (unsigned long)[newLayer countOfPaths]);
    pauseNotifications = false;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self editViewController] redraw];
    });
}
- (void) sendUpdatedNode:(GSNode*)n {
    if(!connected || pauseNotifications) return;
    [self send: [self nodeAsDictionary:n]];
}

- (void) updateNode:(NSDictionary*)d {
    GSLayer *layer = [self editViewController].activeLayer;
    if(!layer) return;
    GSPath *p = [layer pathAtIndex:[d[@"pathindex"] unsignedIntegerValue]];
    if(!p) return;
    GSNode *n = [p nodeAtIndex:[d[@"index"] unsignedIntegerValue]];
    if(!n) return;
    pauseNotifications = true;
    [self updateNode:n fromDictionary:d];
    pauseNotifications = false;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self editViewController] redraw];
    });
}

- (void) updateNode:(GSNode*)n fromDictionary:(NSDictionary*)d {
    [n setPosition:NSMakePoint([d[@"x"] floatValue],[d[@"y"] floatValue])];
    [n setConnection:[d[@"connection"] intValue]];
    [n setType:[d[@"nodetype"] intValue]];
}

@end
