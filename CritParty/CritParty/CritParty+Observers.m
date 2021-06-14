//
//  CritParty+Observers.m
//  CritParty
//
//  Created by Simon Cozens on 29/05/2020.
//  Copyright © 2020 Simon Cozens. All rights reserved.
//

#import "CritParty+Observers.h"
#import <GlyphsCore/NSStringHelpers.h>
#import <AppKit/AppKit.h>


@implementation CritParty (Observers)

-(void)addObserversToEditViewController:(NSViewController<GSGlyphEditViewControllerProtocol> *)editViewController {
	SCLog(@"__addObserversToEditViewController %@", editViewController);
	@try {
		[editViewController removeObserver:self forKeyPath:@"tabBarControl"];
	}
	@catch (NSException * __unused exception) {}
	[editViewController addObserver:self forKeyPath:@"tabBarControl" options:0 context:nil];
}

-(void)addObserversToGraphicView:(NSView<GSGlyphEditViewProtocol>*)graphicView {
	SCLog(@"__addObserversToGraphicView %@", graphicView);
	if (_activeGraphicView) {
		[_activeGraphicView removeObserver:self forKeyPath:@"activeLayer"];
		[_activeGraphicView removeObserver:self forKeyPath:@"selectedRange"];
	}
	_activeGraphicView = graphicView;
	[_activeGraphicView addObserver:self forKeyPath:@"activeLayer" options:0 context:nil];
	[_activeGraphicView addObserver:self forKeyPath:@"selectedRange" options:0 context:nil];
}

-(void)addObserversToLayer:(GSLayer*)l {
	SCLog(@"__addObserversToLayer %@", l);
	if (_activeLayer) {
		[_activeLayer removeObserver:self forKeyPath:@"content"];
	}
	_activeLayer = l;
	[_activeLayer addObserver:self forKeyPath:@"content" options:0 context:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	SCLog(@"Observer: %@ %@ %@", keyPath, object, change);
	if (pauseNotifications) { return; }

	if ([keyPath isEqualToString:@"content"]) {
		[self sendUpdatedLayer:object];
		return;
	}

	if ([keyPath isEqualToString:@"selectedRange"] || [keyPath isEqualToString:@"activeLayer"]) {
		[self sendUpdatedEditView];
	}
}

- (NSDictionary *)layerAsDictionary:(GSLayer *)l {
	return @{
		@"from": myusername,
		@"type": @"layer",
		@"layerid": l.layerId,
		@"layerDict": [l layerDict],
	};
}

- (void)sendUpdatedLayer:(GSLayer*)l {
	if(!connected || pauseNotifications) return;
	[self send:[self layerAsDictionary:l]];
}

- (void)updateLayer:(NSDictionary*)d {
	SCLog(@"Updating layer %@", [self editViewController]);
	GSLayer *layer = [self editViewController].activeLayer;
	if (!layer) {
		SCLog(@"NO layer");
		return;
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		SCLog(@"Updating layer %@", layer);
		self->pauseNotifications = true;
		GSLayer *newLayer = [[GSLayer alloc] initWithLayerDict:d[@"layerDict"]];
		// GSGlyph *g = layer.parent;
		// [self addObserversToLayer:newLayer];
		// [g setLayer:newLayer forKey:d[@"layerId"]];
		SCLog(@"Constructed a layer %@ (paths %lu)", [newLayer layerDict], (unsigned long)[newLayer countOfPaths]);
		layer.paths = newLayer.paths;
		layer.components = newLayer.components;
		layer.anchors = newLayer.anchors;
		layer.annotations = newLayer.annotations;
		if (fabs(layer.width - newLayer.width) > 0.1) {
			layer.width = newLayer.width;
		}
		[self addObserversToLayer:layer];
		self->pauseNotifications = false;
		// [self send:@{@"type":@"setuptabs", @"from": myusername}];
	});
}

- (NSDictionary*)editViewInformation {
	GSDocument* currentDocument = [(GSApplication *)[NSApplication sharedApplication] currentFontDocument];
	NSWindowController<GSWindowControllerProtocol> *windowController = [currentDocument windowController];
	NSViewController<GSGlyphEditViewControllerProtocol>* evc = windowController.activeEditViewController;
	NSMutableDictionary *state = [[NSMutableDictionary alloc] init];
	NSMutableArray *layers = [[NSMutableArray alloc] init];
	state[@"activeIndex"] = [NSNumber numberWithUnsignedLong:[evc.graphicView activeIndex]];
	state[@"writingDirection"] = [NSNumber numberWithInt:[evc writingDirection]];
	for (GSLayer* l in evc.allLayers) {
		UTF32Char inputChar = [currentDocument.font characterForGlyph:l.parent];
		[layers addObject:[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithChar:inputChar], @"char",
						   @([[evc selectedLayers] containsObject:l]), @"selected",
						   [l layerId], @"layerId", nil]]; // if layerID is nil, the args will stop, so 'layerId' will not be in the dict
	}
	state[@"layers"] = layers;
	state[@"type"] = @"tab";
	return state;
}

- (void) sendUpdatedEditView {
	if(!connected || pauseNotifications) return;
	[self send:[self editViewInformation]];
	[self addObserversToLayer:[self editViewController].activeLayer];
	[self addObserversToGraphicView:[self editViewController].graphicView];
	[self addObserversToEditViewController:[self editViewController]];
}

@end
