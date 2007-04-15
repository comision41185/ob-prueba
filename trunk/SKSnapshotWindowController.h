//
//  SKSnapshotWindowController.h
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


@class PDFView, PDFDocument;

@interface SKSnapshotWindowController : NSWindowController {
    IBOutlet PDFView* pdfView;
    NSImage *thumbnail;
    id delegate;
    BOOL miniaturizing;
    BOOL forceOnTop;
}
- (void)setPdfDocument:(PDFDocument *)pdfDocument scaleFactor:(float)factor goToPageNumber:(int)pageNum rect:(NSRect)rect;
- (id)delegate;
- (void)setDelegate:(id)newDelegate;
- (PDFView *)pdfView;
- (NSImage *)thumbnail;
- (void)setThumbnail:(NSImage *)newThumbnail;
- (NSString *)pageLabel;
- (unsigned int)pageIndex;
- (NSDictionary *)pageAndWindow;
- (BOOL)forceOnTop;
- (void)setForceOnTop:(BOOL)flag;
- (NSImage *)thumbnailWithSize:(float)size shadowBlurRadius:(float)shadowBlurRadius shadowOffset:(NSSize)shadowOffset;
- (void)miniaturize;
- (void)deminiaturize;
- (void)handlePageChangedNotification:(NSNotification *)notification;
- (void)handlePDFViewFrameChangedNotification:(NSNotification *)notification;
- (void)handleViewChangedNotification:(NSNotification *)notification;
- (void)handleAnnotationWillChangeNotification:(NSNotification *)notification;
- (void)handleAnnotationDidChangeNotification:(NSNotification *)notification;
- (void)handleDidRemoveAnnotationNotification:(NSNotification *)notification;
@end


@interface SKSnapshotWindow : NSWindow
@end


@interface NSObject (SKSnapshotWindowControllerDelegate)
- (void)snapshotControllerDidFinishSetup:(SKSnapshotWindowController *)controller;
- (void)snapshotControllerWindowWillClose:(SKSnapshotWindowController *)controller;
- (void)snapshotControllerViewDidChange:(SKSnapshotWindowController *)controller;
- (NSRect)snapshotControllerTargetRectForMiniaturize:(SKSnapshotWindowController *)controller;
- (NSRect)snapshotControllerSourceRectForDeminiaturize:(SKSnapshotWindowController *)controller;
@end
