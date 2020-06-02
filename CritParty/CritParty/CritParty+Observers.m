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

-(void) addObserversToGraphicView:(NSView<GSGlyphEditViewProtocol, NSTextInputClient>*)graphicView {
    @try {
        [graphicView removeObserver:self forKeyPath:@"activeLayer"];
        [graphicView removeObserver:self forKeyPath:@"selectedRange"];
    } @catch (NSException * __unused exception) {} // Horrible

    [graphicView addObserver:self forKeyPath:@"activeLayer" options:0 context:nil];
    [graphicView addObserver:self forKeyPath:@"selectedRange" options:0 context:nil];
}

-(void) addObserversToLayer:(GSLayer*)l {
    @try {
        [l removeObserver:self forKeyPath:@"paths"];
        [l removeObserver:self forKeyPath:@"anchors"];
        [l removeObserver:self forKeyPath:@"annotations"];
        [l removeObserver:self forKeyPath:@"LSB"];
        [l removeObserver:self forKeyPath:@"RSB"];
    } @catch (NSException * __unused exception) {} // Horrible
    [l addObserver:self forKeyPath:@"paths" options:0 context:nil];
    [l addObserver:self forKeyPath:@"anchors" options:0 context:nil];
    [l addObserver:self forKeyPath:@"annotations" options:0 context:nil];
    [l addObserver:self forKeyPath:@"LSB" options:0 context:nil];
    [l addObserver:self forKeyPath:@"RSB" options:0 context:nil];
    GSPath* p;
    for (p in l.paths) {
        [self addObserversToPath:p];
    }

    for (NSString* anchorName in l.anchors) {
        [self addObserversToAnchor:l.anchors[anchorName]];
    }

}

-(void) addObserversToPath:(GSPath*)p {
    SCLog(@"Adding obsrerver to path %@", p);
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
    SCLog(@"Adding obsrerver to node %@", n);
    @try {
        [n removeObserver:self forKeyPath:@"connection"];
        [n removeObserver:self forKeyPath:@"type"];
        [n removeObserver:self forKeyPath:@"position"];
    }@ catch (NSException * __unused exception) {} // Horrible
    [n addObserver:self forKeyPath:@"connection" options:0 context:nil];
    [n addObserver:self forKeyPath:@"type" options:0 context:nil];
    [n addObserver:self forKeyPath:@"position" options:0 context:nil];
}

-(void) addObserversToAnchor:(GSAnchor*)a {
    SCLog(@"Adding obsrerver to anchor %@", a);
    @try {
        [a removeObserver:self forKeyPath:@"position"];
    }@ catch (NSException * __unused exception) {} // Horrible
    [a addObserver:self forKeyPath:@"type" options:0 context:nil];
    [a addObserver:self forKeyPath:@"name" options:0 context:nil];
    [a addObserver:self forKeyPath:@"position" options:0 context:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    SCLog(@"Observer: %@ %@ %@", keyPath, object, change);
    if (pauseNotifications) { return; }
    if ([object isKindOfClass:[GSNode class]] &&
        ([keyPath isEqualToString:@"position"] ||
         [keyPath isEqualToString:@"connection"] ||
         [keyPath isEqualToString:@"type"])) {
        [self sendUpdatedNode:object];
        return;
    }
    if ([object isKindOfClass:[GSAnchor class]]) {
        if ([keyPath isEqualToString:@"position"]) {
            [self sendUpdatedAnchor:object];
        } else {
            // Just send the layer
            [self sendUpdatedLayer:((GSAnchor*)object).parent];
        }
        return;
    }

    if ([keyPath isEqualToString:@"nodes"]) {
        [self sendUpdatedPath:object];
        return;
    }
    if ([keyPath isEqualToString:@"paths"] ||
        [keyPath isEqualToString:@"anchors"] ||
        [keyPath isEqualToString:@"LSB"] ||
        [keyPath isEqualToString:@"RSB"]
        ) {
        [self sendUpdatedLayer:object];
        return;
    }
    
    if ([keyPath isEqualToString:@"selectedRange"] || [keyPath isEqualToString:@"activeLayer"]) {
        [self sendUpdatedEditView];
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

- (NSDictionary*)anchorAsDictionary:(GSAnchor*)a {
    return @{
        @"from": myusername,
        @"type": @"anchor",
        @"x": [NSNumber numberWithFloat:a.position.x],
        @"y": [NSNumber numberWithFloat:a.position.y],
        @"name": [a name]
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
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUInteger pathIndex = [d[@"pathindex"] unsignedIntegerValue];
        self->pauseNotifications = true;
        GSPath *p = [[GSPath alloc] initWithPathDict:d[@"pathDict"]];
        [self addObserversToPath:p];
        if (pathIndex <= [layer countOfPaths]-1) {
            [layer replacePathAtIndex:pathIndex withPath:p];
        } else {
            [layer addPath:p];
        }
        self->pauseNotifications = false;
        SCLog(@"Constructed a path %@", p);
        [[self editViewController] redraw];
    });
}

- (void) updateLayer:(NSDictionary*)d {
    SCLog(@"Updating layer");
    GSLayer *layer = [self editViewController].activeLayer;
    if(!layer) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->pauseNotifications = true;
        GSLayer *newLayer = [[GSLayer alloc] initWithLayerDict:d[@"layerDict"]];
    //    GSGlyph *g = layer.parent;
        //    [self addObserversToLayer:newLayer];
    //    [g setLayer:newLayer forKey:d[@"layerId"]];
    //    SCLog(@"Constructed a layer %@ (paths %lu)", [newLayer layerDict], (unsigned long)[newLayer countOfPaths]);
        layer.paths = newLayer.paths;
        layer.anchors = newLayer.anchors;
        layer.annotations = newLayer.annotations;
        layer.LSB = newLayer.LSB;
        layer.RSB = newLayer.RSB;
        [self addObserversToLayer:layer];
        self->pauseNotifications = false;
    //    [self send:@{@"type":@"setuptabs", @"from": myusername}];
        [[self editViewController] redraw];
    });
}

- (void) sendUpdatedAnchor:(GSAnchor*)a {
    if(!connected || pauseNotifications) return;
    [self send: [self anchorAsDictionary:a]];
}

- (void) updateAnchor:(NSDictionary*)d {
    GSLayer *layer = [self editViewController].activeLayer;
    if(!layer) return;
    GSAnchor *a = [layer anchorForName:d[@"name"]];
    if (!a) return;
    pauseNotifications = true;
    // Any other properties will be changed via a layer update
    [a setPosition:NSMakePoint([d[@"x"] floatValue],[d[@"y"] floatValue])];
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
    dispatch_async(dispatch_get_main_queue(), ^{
        self->pauseNotifications = true;
        [self updateNode:n fromDictionary:d];
        self->pauseNotifications = false;
        [[self editViewController] redraw];
    });
}

- (void) updateNode:(GSNode*)n fromDictionary:(NSDictionary*)d {
    [n setPosition:NSMakePoint([d[@"x"] floatValue],[d[@"y"] floatValue])];
    [n setConnection:[d[@"connection"] intValue]];
    [n setType:[d[@"nodetype"] intValue]];
}

- (NSDictionary*)editViewInformation {
    GSDocument* currentDocument = [(GSApplication *)[NSApplication sharedApplication] currentFontDocument];
    NSWindowController<GSWindowControllerProtocol> *windowController = [currentDocument windowController];
    NSViewController<GSGlyphEditViewControllerProtocol>* evc =
    windowController.activeEditViewController;
    NSMutableDictionary *state = [[NSMutableDictionary alloc] init];
    NSMutableArray *layers = [[NSMutableArray alloc] init];
    state[@"activeIndex"] = [NSNumber numberWithUnsignedLong:[evc.graphicView activeIndex]];
    state[@"writingDirection"] = [NSNumber numberWithInt:[evc writingDirection]];
    for (GSLayer* l in evc.allLayers) {
        UTF32Char inputChar = [currentDocument.font characterForGlyph:l.parent];
        [layers addObject:@{
            @"layerId": [l layerId],
            @"char": [[NSString alloc] initWithBytes:&inputChar length:4 encoding:NSUTF32LittleEndianStringEncoding],
            @"selected": [NSNumber numberWithBool:[[evc selectedLayers] containsObject:l]]
        }];
    }
    state[@"layers"] = layers;
    state[@"type"] = @"tab";
    return state;
}

- (void) sendUpdatedEditView {
    if(!connected || pauseNotifications) return;
    // This is looping horribly. :-(
    // For the sake of simplicity, let's say only the HOST can change edit view
    if (mode == CritPartyModeHost) {
        [self send: [self editViewInformation]];
        [self addObserversToLayer:[self editViewController].activeLayer];
        [self addObserversToGraphicView:[self editViewController].graphicView];
    }
}
@end
