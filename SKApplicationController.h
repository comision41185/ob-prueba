//
//  SKApplicationController.h
//  Skim
//
//  Created by Michael McCracken on 12/6/06.
/*
 This software is Copyright (c) 2006,2007
 Michael O. McCracken. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:

 - Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

 - Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

 - Neither the name of Michael O. McCracken nor the names of any
    contributors may be used to endorse or promote products derived
    from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <Cocoa/Cocoa.h>

@class SUUpdater;

@interface SKApplicationController : NSObject {
    IBOutlet SUUpdater *updater;
    BOOL remoteScrolling;
}

+ (void)setupDefaults;

- (IBAction)visitWebSite:(id)sender;

- (IBAction)showPreferencePanel:(id)sender;
- (IBAction)showReleaseNotes:(id)sender;

- (IBAction)editBookmarks:(id)sender;
- (IBAction)openBookmark:(id)sender;

- (SUUpdater *)updater;

- (void)doSpotlightImportIfNeeded;

- (NSString *)applicationSupportPathForDomain:(int)domain create:(BOOL)create;
- (NSString *)pathForApplicationSupportFile:(NSString *)file ofType:(NSString *)extension;

@end


@interface SKSplashWindow : NSWindow
- (id)initWithType:(int)splashType atPoint:(NSPoint)point screen:(NSScreen *)screen;
- (void)show;
@end


@interface SKSplashContentView : NSView {
    int splashType;
}
- (id)initWithType:(int)aSplashType;
@end

