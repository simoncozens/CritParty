//
//  CritParty+FontTransfer.m
//  CritParty
//
//  Created by Simon Cozens on 29/05/2020.
//  Copyright © 2020 Simon Cozens. All rights reserved.
//

#import "CritParty+FontTransfer.h"

#import <AppKit/AppKit.h>

@implementation CritParty (FontTransfer)

- (NSURL*)tempFile {
	NSURL *temporaryDirectoryURL = [NSURL fileURLWithPath: NSTemporaryDirectory()
	                                isDirectory: YES];
	NSString *temporaryFilename =
		[[[NSProcessInfo processInfo] globallyUniqueString]
		 stringByAppendingString:@".glyphs"];
	NSURL *temporaryFileURL =
		[temporaryDirectoryURL
		 URLByAppendingPathComponent:temporaryFilename];
	return temporaryFileURL;
}

- (void)sendFont:(GSFont*)font toUsername:(NSString*)username {
	// Convert to NSData
	NSURL *temporaryFileURL = [self tempFile];
	NSError* outError;
	BOOL result = [font saveToURL:temporaryFileURL type:GSPackageFlatFile error:&outError];
	NSLog(@"Wrote outgoing document on %@", temporaryFileURL);
	if (!result || outError) {
		[self handleConnectionError:@"Couldn't send the font"];
	}
	NSData *data = [NSData dataWithContentsOfURL:temporaryFileURL];

	// Next we split that data into 10k chunks.
	NSUInteger length = [data length];
	NSUInteger chunkSize = 10 * 1024;
	NSUInteger offset = 0;
	NSUInteger chunkIndex = 0;
	NSUInteger totalChunks = ceil(length / (float)chunkSize) - 1; // Chunk count is 0 indexed
	do {
		NSUInteger thisChunkSize = length - offset > chunkSize ? chunkSize : length - offset;
		NSData* chunk = [NSData dataWithBytesNoCopy:(char *)[data bytes] + offset
		                 length:thisChunkSize
		                 freeWhenDone:NO];
		offset += thisChunkSize;
		// do something with chunk
		NSDictionary *message = @{
			@"type": @"glyphsfile",
			@"owner": myusername,
			@"chunk": [NSNumber numberWithUnsignedInteger:chunkIndex],
			@"total": [NSNumber numberWithUnsignedInteger:totalChunks],
			@"data": [chunk base64EncodedStringWithOptions:0]
		};
		SCLog(@"Sending glyphs file %@/%@", message[@"chunk"], message[@"total"]);
		[self sendToGuest:username data:message];
		chunkIndex++;
	} while (offset < length);
}

- (void)handleIncomingFontChunk:(NSDictionary*)d {
	// Chunks are guaranteed to arrive in order
	SCLog(@"__handleIncomingFontChunk: %@", d);
	NSUInteger chunk = [d[@"chunk"] unsignedIntValue];
	NSUInteger total = [d[@"total"] unsignedIntValue];
	if (chunk == 0) {
		// First chunk, create a file
		incomingFontFile = [self tempFile];
		[[NSFileManager defaultManager] createFileAtPath:[incomingFontFile path] contents:nil attributes:nil];
	}
	NSError* error;
	NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingToURL:incomingFontFile error:&error];
	if (error) {
		[self handleConnectionError:[@"Couldn't write incoming file: " stringByAppendingString:[error description]]];
	}
	[fileHandle seekToEndOfFile];
	NSData* data = [[NSData alloc] initWithBase64EncodedString:d[@"data"] options:0];
	[fileHandle writeData:data];
	if (total > 0) {
		[self appendMessage:[NSString stringWithFormat:@"Downloading file %i%%", (int)(100 * chunk / (float)total)]];
	}
	else {
		[self appendMessage:@"Downloaded file"];
	}
	if (chunk == total) {
		[fileHandle closeFile];
		NSLog(@"Open!");
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(documentReceivedAndOpened:) name:@"GSDocumentWasOpenedNotification" object:nil];
		[(GSApplication *)[NSApplication sharedApplication] openDocumentWithContentsOfURL:incomingFontFile display:true];
	}
}

- (void) documentReceivedAndOpened:(NSNotification*)n {
	[self send:@{@"type": @"setuptabs", @"from": myusername}];
	[[NSFileManager defaultManager] removeItemAtURL:incomingFontFile error:nil];
}

@end
