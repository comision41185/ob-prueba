//
//  SKPDFView.h
//  Skim
//
//  Created by Michael McCracken on 12/6/06.
/*
 This software is Copyright (c) 2006-2023
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
#import <Quartz/Quartz.h>
#import "SKBasePDFView.h"
#import "NSDocument_SKExtensions.h"
#import <stdatomic.h>

extern NSString *SKPDFViewDisplaysAsBookChangedNotification;
extern NSString *SKPDFViewDisplaysPageBreaksChangedNotification;
extern NSString *SKPDFViewDisplaysHorizontallyChangedNotification;
extern NSString *SKPDFViewDisplaysRTLChangedNotification;
extern NSString *SKPDFViewAutoScalesChangedNotification;
extern NSString *SKPDFViewToolModeChangedNotification;
extern NSString *SKPDFViewToolModeChangedNotification;
extern NSString *SKPDFViewAnnotationModeChangedNotification;
extern NSString *SKPDFViewTemporaryToolModeChangedNotification;
extern NSString *SKPDFViewCurrentAnnotationChangedNotification;
extern NSString *SKPDFViewDidAddAnnotationNotification;
extern NSString *SKPDFViewDidRemoveAnnotationNotification;
extern NSString *SKPDFViewDidMoveAnnotationNotification;
extern NSString *SKPDFViewReadingBarDidChangeNotification;
extern NSString *SKPDFViewSelectionChangedNotification;
extern NSString *SKPDFViewMagnificationChangedNotification;
extern NSString *SKPDFViewPacerStartedOrStoppedNotification;

extern NSString *SKPDFViewAnnotationKey;
extern NSString *SKPDFViewPageKey;
extern NSString *SKPDFViewOldPageKey;
extern NSString *SKPDFViewNewPageKey;

typedef NS_ENUM(NSInteger, SKToolMode) {
    SKTextToolMode,
    SKMoveToolMode,
    SKMagnifyToolMode,
    SKSelectToolMode,
    SKNoteToolMode
};

typedef NS_ENUM(NSInteger, SKNoteType) {
    SKFreeTextNote,
    SKAnchoredNote,
    SKCircleNote,
    SKSquareNote,
    SKHighlightNote,
    SKUnderlineNote,
    SKStrikeOutNote,
    SKLineNote,
    SKInkNote
};

typedef NS_ENUM(NSInteger, SKTemporaryToolMode) {
    SKNoToolMode,
    SKZoomToolMode,
    SKSnapshotToolMode,
    SKHighlightToolMode = SKHighlightNote,
    SKUnderlineToolMode = SKUnderlineNote,
    SKStrikeOutToolMode = SKStrikeOutNote,
    SKInkToolMode = SKInkNote
};

enum {
    SKDragArea = 1 << 16,
    SKResizeUpDownArea = 1 << 17,
    SKResizeLeftRightArea = 1 << 18,
    SKResizeDiagonal45Area = 1 << 19,
    SKResizeDiagonal135Area = 1 << 20,
    SKResizeRightArea = 1 << 21,
    SKResizeUpArea = 1 << 22,
    SKResizeLeftArea = 1 << 23,
    SKResizeDownArea = 1 << 24,
    SKReadingBarArea = 1 << 25,
    SKSpecialToolArea = 1 << 26,
    SKTemporaryToolArea = 1 << 27
};

enum {
     kPDFDisplayHorizontalContinuous = 4
};

@protocol SKPDFViewDelegate;

@class SKReadingBar, SKTransitionController, SKTypeSelectHelper, SKNavigationWindow, SKTextNoteEditor, SKSyncDot, SKLoupeController, SKLayerController;

@interface SKPDFView : SKBasePDFView {
    SKToolMode toolMode;
    SKTemporaryToolMode temporaryToolMode;
    SKNoteType annotationMode;
    SKInteractionMode interactionMode;
    
    NSInteger navigationMode;
    SKNavigationWindow *navWindow;
    
    SKReadingBar *readingBar;
    
    NSTimer *pacerTimer;
    CGFloat pacerSpeed;
    CGFloat pacerWaitTime;
    
    SKTransitionController *transitionController;
    
    SKTypeSelectHelper *typeSelectHelper;
    
	PDFAnnotation *currentAnnotation;
	PDFAnnotation *highlightAnnotation;
    
    SKTextNoteEditor *editor;
    
    NSRect selectionRect;
    NSUInteger selectionPageIndex;
    
    PDFPage *rewindPage;
    
    SKSyncDot *syncDot;
    
    SKLayerController *highlightLayerController;
    _Atomic(NSInteger) highlightLayerState;
    
    SKLoupeController *loupeController;
    
    CGFloat gestureRotation;
    NSUInteger gesturePageIndex;
    
    NSInteger minHistoryIndex;
    
    NSTrackingArea *trackingArea;
    
    NSInteger spellingTag;
    
    NSInteger laserPointerColor;
    
    _Atomic(BOOL) inKeyWindow;
    
    struct _pdfvFlags {
        unsigned int hideNotes:1;
        unsigned int wantsNewUndoGroup:1;
        unsigned int cursorHidden:1;
        unsigned int useArrowCursorInPresentation:1;
    } pdfvFlags;
}

@property (nonatomic) PDFDisplayMode extendedDisplayMode;
@property (nonatomic) BOOL displaysHorizontally;
@property (nonatomic) BOOL displaysRightToLeft;
@property (nonatomic) SKToolMode toolMode;
@property (nonatomic) SKNoteType annotationMode;
@property (nonatomic) SKTemporaryToolMode temporaryToolMode;
@property (nonatomic) SKInteractionMode interactionMode;
@property (nonatomic, retain) PDFAnnotation *currentAnnotation;
@property (nonatomic, readonly, getter=isEditing) BOOL editing;
@property (nonatomic, readonly, getter=isZooming) BOOL zooming;
@property (nonatomic) NSRect currentSelectionRect;
@property (nonatomic, retain) PDFPage *currentSelectionPage;
@property (nonatomic, readonly) CGFloat currentMagnification;
@property (nonatomic) BOOL hideNotes;
@property (nonatomic, readonly) BOOL hasReadingBar;
@property (readonly) SKReadingBar *readingBar;
@property (nonatomic) CGFloat pacerSpeed;
@property (nonatomic, readonly) BOOL hasPacer;
@property (nonatomic, readonly) SKTransitionController *transitionController;
@property (nonatomic, retain) SKTypeSelectHelper *typeSelectHelper;

@property (nonatomic) BOOL needsRewind;

- (void)toggleReadingBar;

- (void)togglePacer;

- (IBAction)delete:(id)sender;
- (IBAction)paste:(id)sender;
- (IBAction)alternatePaste:(id)sender;
- (IBAction)pasteAsPlainText:(id)sender;
- (IBAction)copy:(id)sender;
- (IBAction)cut:(id)sender;
- (IBAction)deselectAll:(id)sender;
- (IBAction)autoSelectContent:(id)sender;
- (IBAction)changeToolMode:(id)sender;
- (IBAction)changeAnnotationMode:(id)sender;

- (void)setDisplayModeAndRewind:(PDFDisplayMode)mode;
- (void)setExtendedDisplayModeAndRewind:(PDFDisplayMode)mode;
- (void)setDisplaysHorizontallyAndRewind:(BOOL)flag;
- (void)setDisplaysRightToLeftAndRewind:(BOOL)flag;
- (void)setDisplayBoxAndRewind:(PDFDisplayBox)box;
- (void)setDisplaysAsBookAndRewind:(BOOL)asBook;

- (void)zoomLog:(id)sender;
- (void)toggleAutoActualSize:(id)sender;
- (void)exitPresentation:(id)sender;

- (void)addAnnotationForContext:(id)sender;
- (void)addAnnotationWithType:(SKNoteType)annotationType;
- (void)addAnnotation:(PDFAnnotation *)annotation toPage:(PDFPage *)page;
- (void)removeCurrentAnnotation:(id)sender;
- (void)removeThisAnnotation:(id)sender;
- (void)removeAnnotation:(PDFAnnotation *)annotation;

- (void)editCurrentAnnotation:(id)sender;
- (void)editThisAnnotation:(id)sender;
- (void)editAnnotation:(PDFAnnotation *)annotation;

- (void)autoSizeCurrentAnnotation:(PDFAnnotation *)annotation;

- (void)selectNextCurrentAnnotation:(id)sender;
- (void)selectPreviousCurrentAnnotation:(id)sender;

- (void)scrollAnnotationToVisible:(PDFAnnotation *)annotation;
- (void)displayLineAtPoint:(NSPoint)point inPageAtIndex:(NSUInteger)pageIndex select:(BOOL)select showReadingBar:(BOOL)showBar;
- (void)zoomToRect:(NSRect)rect onPage:(PDFPage *)page;

- (void)takeSnapshot:(id)sender;

- (void)resetPDFToolTipRects;
- (void)removePDFToolTipRects;

- (void)resetHistory;

- (id <SKPDFViewDelegate>)delegate;
- (void)setDelegate:(id <SKPDFViewDelegate>)newDelegate;

- (NSString *)currentColorDefaultKeyForAlternate:(BOOL)isAlt;

@end

#pragma mark -

@protocol SKPDFViewDelegate <PDFViewDelegate>
@optional
- (void)PDFViewDidBeginEditing:(PDFView *)sender;
- (void)PDFViewDidEndEditing:(PDFView *)sender;
- (void)PDFView:(PDFView *)sender editAnnotation:(PDFAnnotation *)annotation;
- (void)PDFView:(PDFView *)sender showSnapshotAtPageNumber:(NSInteger)pageNum forRect:(NSRect)rect scaleFactor:(CGFloat)scaleFactor autoFits:(BOOL)autoFits;
- (void)PDFViewExitPresentation:(PDFView *)sender;
- (void)PDFViewTogglePages:(PDFView *)sender;
- (void)PDFViewToggleContents:(PDFView *)sender;
- (void)PDFViewPerformHideFind:(PDFView *)sender;
- (BOOL)PDFViewIsFindVisible:(PDFView *)sender;
@end
