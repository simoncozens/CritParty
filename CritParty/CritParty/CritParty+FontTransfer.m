//
//  CritParty+FontTransfer.m
//  CritParty
//
//  Created by Simon Cozens on 29/05/2020.
//  Copyright © 2020 Simon Cozens. All rights reserved.
//

#import "CritParty+FontTransfer.h"

#import <AppKit/AppKit.h>

@interface GSApplication : NSApplication
@property (weak, nonatomic, nullable) GSDocument* currentFontDocument;
- (GSDocument*)openDocumentWithContentsOfURL:(NSURL*)url display:(bool)display;
@end

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
    BOOL result = [font saveToURL:temporaryFileURL error:&outError];
    NSLog(@"Wrote outgoing document on %@", temporaryFileURL);
    if (!result || outError) {
        [self handleConnectionError:@"Couldn't send the font"];
    }
    NSData *data = [NSData dataWithContentsOfURL:temporaryFileURL];
    
    // Next we split that data into 16k chunks.
    NSUInteger length = [data length];
    NSUInteger chunkSize = 16 * 1024;
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
        NSLog(@"Sending glyphs file %@/%@", message[@"chunk"], message[@"total"]);
        [self sendToGuest:username data:message];
        chunkIndex++;
    } while (offset < length);
}

- (void)handleIncomingFontChunk:(NSDictionary*)d {
    // Chunks are guaranteed to arrive in order
    if ([d[@"chunk"] unsignedIntValue] == 0) {
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
    NSData* chunk = [[NSData alloc] initWithBase64EncodedString:d[@"data"] options:0];
    [fileHandle writeData:chunk];
    [self appendMessage:[NSString stringWithFormat:@"Downloading file %i%%", (int)(100 * [d[@"chunk"] unsignedIntValue] / (float)[d[@"total"] unsignedIntValue])]];
    if ([d[@"chunk"] unsignedIntValue] == [d[@"total"] unsignedIntValue]) {
        [fileHandle closeFile];
        NSLog(@"Open!");
        [(GSApplication *)[NSApplication sharedApplication] openDocumentWithContentsOfURL: incomingFontFile display: true];
    }
}

@end
