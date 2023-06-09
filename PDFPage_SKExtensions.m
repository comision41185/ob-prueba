//
//  PDFPage_SKExtensions.m
//  Skim
//
//  Created by Christiaan Hofman on 2/16/07.
/*
 This software is Copyright (c) 2007-2023
 Christiaan Hofman. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:

 - Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

 - Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

 - Neither the name of Christiaan Hofman nor the names of any
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

#import "PDFPage_SKExtensions.h"
#import <SkimNotes/SkimNotes.h>
#import "SKMainDocument.h"
#import "SKPDFView.h"
#import "SKReadingBar.h"
#import "PDFSelection_SKExtensions.h"
#import "SKRuntime.h"
#import "NSBitmapImageRep_SKExtensions.h"
#import "SKStringConstants.h"
#import "NSCharacterSet_SKExtensions.h"
#import "NSGeometry_SKExtensions.h"
#import "NSData_SKExtensions.h"
#import "NSUserDefaults_SKExtensions.h"
#import "SKMainWindowController.h"
#import "PDFAnnotation_SKExtensions.h"
#import "PDFAnnotationMarkup_SKExtensions.h"
#import "PDFAnnotationInk_SKExtensions.h"
#import "NSPointerArray_SKExtensions.h"
#import "NSDocument_SKExtensions.h"
#import "PDFDocument_SKExtensions.h"
#import "NSImage_SKExtensions.h"
#import "NSShadow_SKExtensions.h"
#import "PDFView_SKExtensions.h"
#import "SKRuntime.h"
#import "NSPasteboard_SKExtensions.h"
#import "NSURL_SKExtensions.h"
#import "SKLine.h"

NSString *SKPDFPageBoundsDidChangeNotification = @"SKPDFPageBoundsDidChangeNotification";

NSString *SKPDFPagePageKey = @"page";
NSString *SKPDFPageActionKey = @"action";
NSString *SKPDFPageActionCrop = @"crop";
NSString *SKPDFPageActionResize = @"resize";
NSString *SKPDFPageActionRotate = @"rotate";

#define SKAutoCropBoxMarginWidthKey @"SKAutoCropBoxMarginWidth"
#define SKAutoCropBoxMarginHeightKey @"SKAutoCropBoxMarginHeight"

@implementation PDFPage (SKExtensions) 

- (void)fallback_transformContext:(CGContextRef)context forBox:(PDFDisplayBox)box {
    NSRect bounds = [self boundsForBox:box];
    CGContextRotateCTM(context, -[self rotation] * M_PI_2 / 90.0);
    switch ([self rotation]) {
        case 0:   CGContextTranslateCTM(context, -NSMinX(bounds), -NSMinY(bounds)); break;
        case 90:  CGContextTranslateCTM(context, -NSMaxX(bounds), -NSMinY(bounds)); break;
        case 180: CGContextTranslateCTM(context, -NSMaxX(bounds), -NSMaxY(bounds)); break;
        case 270: CGContextTranslateCTM(context, -NSMinX(bounds), -NSMaxY(bounds)); break;
    }
}

+ (void)load {
    SKAddInstanceMethodImplementationFromSelector(self, @selector(transformContext:forBox:), @selector(fallback_transformContext:forBox:));
}

static BOOL usesSequentialPageNumbering = NO;

+ (BOOL)usesSequentialPageNumbering {
    return usesSequentialPageNumbering;
}

+ (void)setUsesSequentialPageNumbering:(BOOL)flag {
    usesSequentialPageNumbering = flag;
}

- (NSBitmapImageRep *)newBitmapImageRepForBox:(PDFDisplayBox)box {
    NSRect bounds = [self boundsForBox:box];
    NSBitmapImageRep *imageRep;
    imageRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                       pixelsWide:(NSInteger)NSWidth(bounds)
                                                       pixelsHigh:(NSInteger)NSHeight(bounds)
                                                    bitsPerSample:8 
                                                  samplesPerPixel:4
                                                         hasAlpha:YES 
                                                         isPlanar:NO 
                                                   colorSpaceName:NSCalibratedRGBColorSpace 
                                                     bitmapFormat:0 
                                                      bytesPerRow:0 
                                                     bitsPerPixel:32];
    if (imageRep) {
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:imageRep]];
        [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationNone];
        [[NSGraphicsContext currentContext] setShouldAntialias:NO];
        if ([self rotation]) {
            NSAffineTransform *transform = [NSAffineTransform transform];
            switch ([self rotation]) {
                case 90:  [transform translateXBy:NSWidth(bounds) yBy:0.0]; break;
                case 180: [transform translateXBy:NSHeight(bounds) yBy:NSWidth(bounds)]; break;
                case 270: [transform translateXBy:0.0 yBy:NSHeight(bounds)]; break;
            }
            [transform rotateByDegrees:[self rotation]];
            [transform concat];
        }
        [self drawWithBox:box]; 
        [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationDefault];
        [NSGraphicsContext restoreGraphicsState];
    }
    return imageRep;
}

// this will be cached in our custom subclass
- (NSRect)foregroundBox {
    CGFloat marginWidth = [[NSUserDefaults standardUserDefaults] floatForKey:SKAutoCropBoxMarginWidthKey];
    CGFloat marginHeight = [[NSUserDefaults standardUserDefaults] floatForKey:SKAutoCropBoxMarginHeightKey];
    NSBitmapImageRep *imageRep = [self newBitmapImageRepForBox:kPDFDisplayBoxMediaBox];
    NSRect bounds = [self boundsForBox:kPDFDisplayBoxMediaBox];
    NSRect foregroundBox = [imageRep foregroundRect];
    if (imageRep == nil) {
        foregroundBox = bounds;
    } else if (NSIsEmptyRect(foregroundBox)) {
        foregroundBox.origin = SKIntegralPoint(SKCenterPoint(bounds));
        foregroundBox.size = NSZeroSize;
    } else {
        foregroundBox.origin = SKAddPoints(foregroundBox.origin, bounds.origin);
    }
    [imageRep release];
    return NSIntersectionRect(NSInsetRect(foregroundBox, -marginWidth, -marginHeight), bounds);
}

- (NSImage *)thumbnailWithSize:(CGFloat)aSize forBox:(PDFDisplayBox)box {
    return  [self thumbnailWithSize:aSize forBox:box readingBar:nil];
}

- (NSImage *)thumbnailWithSize:(CGFloat)aSize forBox:(PDFDisplayBox)box readingBar:(SKReadingBar *)readingBar {
    CGFloat shadowBlurRadius = round(aSize / 32.0);
    NSArray *highlights = readingBar ? @[readingBar] : nil;
    return  [self thumbnailWithSize:aSize forBox:box shadowBlurRadius:shadowBlurRadius highlights:highlights];
}

- (NSImage *)thumbnailWithSize:(CGFloat)aSize forBox:(PDFDisplayBox)box shadowBlurRadius:(CGFloat)shadowBlurRadius highlights:(NSArray *)highlights {
    NSRect bounds = [self boundsForBox:box];
    NSSize pageSize = bounds.size;
    CGFloat scale = 1.0;
    NSSize thumbnailSize;
    CGFloat shadowOffset = shadowBlurRadius > 0.0 ? - ceil(shadowBlurRadius * 0.75) : 0.0;
    NSRect pageRect = NSZeroRect;
    NSImage *image;
    
    if ([self rotation] % 180 == 90)
        pageSize = NSMakeSize(pageSize.height, pageSize.width);
    
    if (aSize > 0.0) {
        if (pageSize.height > pageSize.width)
            thumbnailSize = NSMakeSize(round((aSize - 2.0 * shadowBlurRadius) * pageSize.width / pageSize.height + 2.0 * shadowBlurRadius), aSize);
        else
            thumbnailSize = NSMakeSize(aSize, round((aSize - 2.0 * shadowBlurRadius) * pageSize.height / pageSize.width + 2.0 * shadowBlurRadius));
        scale = fmax((thumbnailSize.width - 2.0 * shadowBlurRadius) / pageSize.width, (thumbnailSize.height - 2.0 * shadowBlurRadius) / pageSize.height);
    } else {
        thumbnailSize = NSMakeSize(pageSize.width + 2.0 * shadowBlurRadius, pageSize.height + 2.0 * shadowBlurRadius);
    }
    
    pageRect.size = thumbnailSize;
    
    if (shadowBlurRadius > 0.0) {
        pageRect = NSInsetRect(pageRect, shadowBlurRadius, shadowBlurRadius);
        pageRect.origin.y -= shadowOffset;
    }
    
    image = [[[NSImage alloc] initWithSize:thumbnailSize] autorelease];
    
    [image lockFocus];
    
    [[NSGraphicsContext currentContext] setImageInterpolation:[[NSUserDefaults standardUserDefaults] integerForKey:SKInterpolationQualityKey] + 1];
    
    [NSGraphicsContext saveGraphicsState];
    [[NSColor whiteColor] setFill];
    if (shadowBlurRadius > 0.0)
        [NSShadow setShadowWithWhite:0.0 alpha:0.33333 blurRadius:shadowBlurRadius yOffset:shadowOffset];
    NSRectFill(pageRect);
    [NSGraphicsContext restoreGraphicsState];
    
    if (fabs(scale - 1.0) > 0.0 || shadowBlurRadius > 0.0) {
        NSAffineTransform *transform = [NSAffineTransform transform];
        if (shadowBlurRadius > 0.0)
            [transform translateXBy:NSMinX(pageRect) yBy:NSMinY(pageRect)];
        [transform scaleBy:scale];
        [transform concat];
    }
    
    [self drawWithBox:box]; 
    
    for (id highlight in highlights) {
        // highlight should be a PDFSelection or SKReadingBar
        if ([highlight respondsToSelector:@selector(drawForPage:withBox:active:)])
            [highlight drawForPage:self withBox:box active:YES];
    }
    
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationDefault];
    
    [image unlockFocus];
    
    return image;
}

- (NSAttributedString *)thumbnailAttachmentWithSize:(CGFloat)aSize {
    NSImage *image = [self thumbnailWithSize:aSize forBox:kPDFDisplayBoxCropBox];
    
    NSFileWrapper *wrapper = [[NSFileWrapper alloc] initRegularFileWithContents:[image TIFFRepresentation]];
    NSString *filename = [NSString stringWithFormat:@"page_%lu.tiff", (unsigned long)([self pageIndex] + 1)];
    [wrapper setFilename:filename];
    [wrapper setPreferredFilename:filename];

    NSTextAttachment *attachment = [[NSTextAttachment alloc] initWithFileWrapper:wrapper];
    [wrapper release];
    NSAttributedString *attrString = [NSAttributedString attributedStringWithAttachment:attachment];
    [attachment release];
    
    return attrString;
}

- (NSAttributedString *)thumbnailAttachment { return [self thumbnailAttachmentWithSize:0.0]; }

- (NSAttributedString *)thumbnail512Attachment { return [self thumbnailAttachmentWithSize:512.0]; }

- (NSAttributedString *)thumbnail256Attachment { return [self thumbnailAttachmentWithSize:256.0]; }

- (NSAttributedString *)thumbnail128Attachment { return [self thumbnailAttachmentWithSize:128.0]; }

- (NSAttributedString *)thumbnail64Attachment { return [self thumbnailAttachmentWithSize:64.0]; }

- (NSAttributedString *)thumbnail32Attachment { return [self thumbnailAttachmentWithSize:32.0]; }

- (NSData *)PDFDataForRect:(NSRect)rect {
    if (NSEqualRects(rect, NSZeroRect))
        return [self dataRepresentation];
    if (NSIsEmptyRect(rect))
        return nil;
    
    NSData *data = nil;
    PDFPage *page = [self copy];
    
    if (RUNNING(10_11)) {
        // on 10.11 the media box is shifted back to the origin without the contents being shifted
        [page setBounds:rect forBox:kPDFDisplayBoxCropBox];
    } else {
        [page setBounds:rect forBox:kPDFDisplayBoxMediaBox];
        [page setBounds:NSZeroRect forBox:kPDFDisplayBoxCropBox];
    }
    [page setBounds:NSZeroRect forBox:kPDFDisplayBoxBleedBox];
    [page setBounds:NSZeroRect forBox:kPDFDisplayBoxTrimBox];
    [page setBounds:NSZeroRect forBox:kPDFDisplayBoxArtBox];
    data = [page dataRepresentation];
    [page release];
    
    return data;
}

- (NSData *)TIFFDataForRect:(NSRect)rect {
    PDFDisplayBox box = NSEqualRects(rect, [self boundsForBox:kPDFDisplayBoxCropBox]) ? kPDFDisplayBoxCropBox : kPDFDisplayBoxMediaBox;
    NSImage *pageImage = [self thumbnailWithSize:0.0 forBox:box shadowBlurRadius:0.0 highlights:nil];
    NSRect bounds = [self boundsForBox:box];
    
    if (NSEqualRects(rect, NSZeroRect) || NSEqualRects(rect, bounds))
        return [pageImage TIFFRepresentation];
    if (NSIsEmptyRect(rect))
        return nil;
    
    NSAffineTransform *transform = [self affineTransformForBox:box];
    NSRect sourceRect = SKTransformRect(transform, rect);
    NSRect destRect = sourceRect;
    destRect.origin = NSZeroPoint;
    
    NSImage *image = [[[NSImage alloc] initWithSize:destRect.size] autorelease];
    [image lockFocus];
    [pageImage drawInRect:destRect fromRect:sourceRect operation:NSCompositingOperationCopy fraction:1.0];
    [image unlockFocus];
    
    return [image TIFFRepresentation];
}

// the page is set as owner in -filePromise
- (void)pasteboard:(NSPasteboard *)pboard item:(NSPasteboardItem *)item provideDataForType:(NSString *)type {
    if ([type isEqualToString:(NSString *)kPasteboardTypeFileURLPromise]) {
        NSURL *dropDestination = [pboard pasteLocationURL];
        NSString *filename = [NSString stringWithFormat:@"%@ %c %@", ([[[self containingDocument] displayName] stringByDeletingPathExtension] ?: @"PDF"), '-', [NSString stringWithFormat:NSLocalizedString(@"Page %@", @""), [self displayLabel]]];
        NSURL *fileURL = [dropDestination URLByAppendingPathComponent:filename isDirectory:NO];
        NSString *pathExt = nil;
        NSData *data = nil;
        
        if ([[self document] allowsPrinting]) {
            pathExt = @"pdf";
            data = [self dataRepresentation];
        } else {
            pathExt = @"tiff";
            data = [self TIFFDataForRect:[self boundsForBox:kPDFDisplayBoxCropBox]];
        }
        
        fileURL = [[fileURL URLByAppendingPathExtension:pathExt] uniqueFileURL];
        if ([data writeToURL:fileURL atomically:YES])
            [item setString:[fileURL absoluteString] forType:type];
    } else if ([type isEqualToString:NSPasteboardTypePDF]) {
        [item setData:[self dataRepresentation] forType:type];
    } else if ([type isEqualToString:NSPasteboardTypeTIFF]) {
        [item setData:[self TIFFDataForRect:[self boundsForBox:kPDFDisplayBoxCropBox]] forType:type];
    }
}

#pragma mark NSFilePromiseProviderDelegate protocol

// the page is set as delegate in -filePromise
- (NSString *)filePromiseProvider:(NSFilePromiseProvider *)filePromiseProvider fileNameForType:(NSString *)fileType {
    NSString *filename = [NSString stringWithFormat:@"%@ %c %@", ([[[self containingDocument] displayName] stringByDeletingPathExtension] ?: @"PDF"), '-', [NSString stringWithFormat:NSLocalizedString(@"Page %@", @""), [self displayLabel]]];
    NSString *pathExt = [[self document] allowsPrinting] ? @"pdf" : @"tiff";
    return [filename stringByAppendingPathExtension:pathExt];
}

- (void)filePromiseProvider:(NSFilePromiseProvider *)filePromiseProvider writePromiseToURL:(NSURL *)fileURL completionHandler:(void (^)(NSError *))completionHandler {
    NSData *data = nil;
    NSError *error = nil;
    if ([[self document] allowsPrinting])
        data = [self dataRepresentation];
    else
        data = [self TIFFDataForRect:[self boundsForBox:kPDFDisplayBoxCropBox]];
    [data writeToURL:fileURL options:NSDataWritingAtomic error:&error];
    completionHandler(error);
}

- (id<NSPasteboardWriting>)filePromise {
    if ([[self document] isLocked] == NO) {
        NSString *fileUTI = [[self document] allowsPrinting] ? (NSString *)kUTTypePDF : (NSString *)kUTTypeTIFF;
        Class promiseClass = NSClassFromString(@"NSFilePromiseProvider");
        if (promiseClass) {
            return [[[promiseClass alloc] initWithFileType:fileUTI delegate:self] autorelease];
        } else {
            NSString *pdfType = [[self document] allowsPrinting] ? NSPasteboardTypePDF : nil;
            NSPasteboardItem *item = [[[NSPasteboardItem alloc] init] autorelease];
            [item setString:fileUTI forType:(NSString *)kPasteboardTypeFilePromiseContent];
            [item setDataProvider:self forTypes:@[(NSString *)kPasteboardTypeFileURLPromise, NSPasteboardTypeTIFF, pdfType]];
            return item;
        }
    }
    return nil;
}

- (void)writeToClipboard {
    if ([[self document] isLocked] == NO) {
        NSData *tiffData = [self TIFFDataForRect:[self boundsForBox:kPDFDisplayBoxCropBox]];
        NSPasteboardItem *pboardItem = [[[NSPasteboardItem alloc] init] autorelease];
        if ([[self document] allowsPrinting])
            [pboardItem setData:[self dataRepresentation] forType:NSPasteboardTypePDF];
        [pboardItem setData:tiffData forType:NSPasteboardTypeTIFF];
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        [pboard clearContents];
        [pboard writeObjects:@[pboardItem]];
    }
}

- (NSURL *)skimURL {
    NSURL *fileURL = [[self containingDocument] fileURL];
    if (fileURL == nil)
        return nil;
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:fileURL resolvingAgainstBaseURL:NO];
    [components setScheme:@"skim"];
    [components setFragment:[NSString stringWithFormat:@"page=%lu", (unsigned long)([self pageIndex] + 1)]];
    NSURL *skimURL = [components URL];
    [components release];
    return skimURL;
}

static inline BOOL lineRectsOverlap(NSRect r1, NSRect r2, BOOL rotated) {
    if (rotated)
        return (NSMaxX(r1) > NSMidX(r2) && NSMidX(r1) < NSMaxX(r2)) || (NSMidX(r1) > NSMinX(r2) && NSMinX(r1) < NSMidX(r2));
    else
        return (NSMinY(r1) < NSMidY(r2) && NSMidY(r1) > NSMinY(r2)) || (NSMidY(r1) < NSMaxY(r2) && NSMaxY(r1) > NSMidY(r2));
}

- (NSPointerArray *)lineRects {
    NSPointerArray *lines = [NSPointerArray rectPointerArray];
    PDFSelection *sel = [self selectionForRect:[self boundsForBox:kPDFDisplayBoxCropBox]];
    CGFloat lastOrder = -CGFLOAT_MAX;
    NSUInteger i;
    NSRect rect;
    NSMutableIndexSet *verticalLines = [NSMutableIndexSet indexSet];
    BOOL rotated = ([self lineDirectionAngle] % 180) == 0;
    
    for (PDFSelection *s in [sel selectionsByLine]) {
        NSString *str = [s string];
        rect = [s boundsForPage:self];
        if (NSIsEmptyRect(rect) == NO && [str rangeOfCharacterFromSet:[NSCharacterSet nonWhitespaceAndNewlineCharacterSet]].length) {
            CGFloat order = [self sortOrderForBounds:rect];
            if (lastOrder <= order) {
                i = [lines count];
                lastOrder = order;
            } else {
                for (i = [lines count] - 1; i > 0; i--) {
                    if ([self sortOrderForBounds:[lines rectAtIndex:i - 1]] <= order)
                        break;
                }
            }
            if ([str length] > 1 && (rotated ? NSHeight(rect) <= NSHeight(rect) : NSWidth(rect) <= NSHeight(rect)))
                [verticalLines addIndex:i];
            [lines insertPointer:&rect atIndex:i];
        }
    }
    
    NSRect prevRect = NSZeroRect;
    BOOL prevVertical = NO;
    BOOL vertical = NO;
    NSUInteger offset = 0;
    
    for (i = 0; i < [lines count]; i++) {
        rect = [lines rectAtIndex:i];
        vertical = [verticalLines containsIndex:i + offset];
        if (i > 0 && vertical == NO && prevVertical == NO && lineRectsOverlap(prevRect, rect, rotated)) {
            rect = NSUnionRect(prevRect, rect);
            [lines removePointerAtIndex:i--];
            [lines replacePointerAtIndex:i withPointer:&rect];
            offset++;
        }
        prevRect = rect;
        prevVertical = vertical;
    }
    
    return lines;
}

static inline BOOL pointBelowRect(NSPoint point, NSRect rect, NSInteger lineDirectionAngle) {
    switch (lineDirectionAngle) {
        case 0:   return point.x > NSMaxX(rect);
        case 90:  return point.y > NSMaxY(rect);
        case 180: return point.x < NSMinX(rect);
        case 270: return point.y < NSMinY(rect);
        default:  return point.y < NSMinY(rect);
    }
}

static inline BOOL pointAboveRect(NSPoint point, NSRect rect, NSInteger lineDirectionAngle) {
    switch (lineDirectionAngle) {
        case 0:   return point.x < NSMinX(rect);
        case 90:  return point.y < NSMinY(rect);
        case 180: return point.x > NSMaxX(rect);
        case 270: return point.y > NSMaxY(rect);
        default:  return point.y > NSMaxY(rect);
    }
}

- (NSInteger)indexOfLineRectAtPoint:(NSPoint)point lower:(BOOL)lower {
    NSPointerArray *rectArray = [self lineRects];
    NSInteger i = [rectArray count];
    BOOL preferNext = NO;
    NSInteger angle = [self lineDirectionAngle];
    
    while (i-- > 0) {
        NSRect rect = [rectArray rectAtIndex:i];
        if (pointAboveRect(point, rect, angle))
            preferNext = lower == NO;
        else
            return (preferNext && pointBelowRect(point, rect, angle)) ? i + 1 : i;
    }
    return -1;
}

- (NSUInteger)pageIndex {
    return [[self document] indexForPage:self];
}

- (NSString *)sequentialLabel {
    return [NSString stringWithFormat:@"%lu", (unsigned long)([self pageIndex] + 1)];
}

- (NSString *)displayLabel {
    NSString *label = nil;
    if ([[self class] usesSequentialPageNumbering] == NO)
        label = [self label];
    return label ?: [self sequentialLabel];
}

- (NSInteger)intrinsicRotation {
    return CGPDFPageGetRotationAngle([self pageRef]);
}

static inline NSInteger distanceForAngle(NSInteger angle, NSRect bounds, NSRect pageBounds) {
    switch (angle) {
        case 0:   return (NSInteger)NSMinX(bounds);
        case 90:  return (NSInteger)NSMinY(bounds);
        case 180: return (NSInteger)(NSMaxX(pageBounds) - NSMaxX(bounds));
        case 270: return (NSInteger)(NSMaxY(pageBounds) - NSMaxY(bounds));
        default:  return (NSInteger)NSMinX(bounds);
    }
}

- (NSInteger)characterDirectionAngle {
    return ([self intrinsicRotation] + [[self document] languageDirectionAngles].characterDirection) % 360;
}

- (NSInteger)lineDirectionAngle {
    return ([self intrinsicRotation] + [[self document] languageDirectionAngles].lineDirection) % 360;
}

- (CGFloat)sortOrderForBounds:(NSRect)bounds {
    // count pixels from start of page in reading direction until the corner of the bounds, in intrinsically rotated page
    NSInteger characterAngle = [self characterDirectionAngle];
    NSInteger lineAngle = [self lineDirectionAngle];
    // first get the area in pixels from the start of the page to the line for the bounds
    NSRect pageBounds = [self boundsForBox:kPDFDisplayBoxMediaBox];
    CGFloat sortOrder = floor(distanceForAngle(lineAngle, bounds, pageBounds));
    sortOrder *= (lineAngle % 180) ? NSWidth(pageBounds) : NSHeight(pageBounds);
    // next add the pixels from the start of the line to the bounds
    sortOrder += distanceForAngle(characterAngle, bounds, pageBounds);
    return sortOrder;
}

- (BOOL)isEditable {
    return NO;
}

- (NSAffineTransform *)affineTransformForBox:(PDFDisplayBox)box {
    NSRect bounds = [self boundsForBox:box];
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform rotateByDegrees:-[self rotation]];
    switch ([self rotation]) {
        case 0:   [transform translateXBy:-NSMinX(bounds) yBy:-NSMinY(bounds)]; break;
        case 90:  [transform translateXBy:-NSMaxX(bounds) yBy:-NSMinY(bounds)]; break;
        case 180: [transform translateXBy:-NSMaxX(bounds) yBy:-NSMaxY(bounds)]; break;
        case 270: [transform translateXBy:-NSMinX(bounds) yBy:-NSMaxY(bounds)]; break;
    }
    return transform;
}

#pragma mark Scripting support

- (NSScriptObjectSpecifier *)objectSpecifier {
    NSDocument *document = [self containingDocument];
	NSUInteger idx = [self pageIndex];
    
    if (document && idx != NSNotFound) {
        NSScriptObjectSpecifier *containerRef = [document objectSpecifier];
        return [[[NSIndexSpecifier allocWithZone:[self zone]] initWithContainerClassDescription:[containerRef keyClassDescription] containerSpecifier:containerRef key:@"pages" index:idx] autorelease];
    } else {
        return nil;
    }
}

- (NSDocument *)containingDocument {
    return [[self document] containingDocument];
}

- (NSUInteger)index {
    return [self pageIndex] + 1;
}

- (NSInteger)rotationAngle {
    return [self rotation];
}

- (void)setRotationAngle:(NSInteger)angle {
    if ([self isEditable] && angle != [self rotation]) {
        NSUndoManager *undoManager = [[self containingDocument] undoManager];
        [(PDFPage *)[undoManager prepareWithInvocationTarget:self] setRotationAngle:[self rotation]];
        [undoManager setActionName:NSLocalizedString(@"Rotate Page", @"Undo action name")];
        // this will dirty the document, even though no saveable change has been made
        // but we cannot undo the document change count because there may be real changes to the document in the script
        
        [self setRotation:angle];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:SKPDFPageBoundsDidChangeNotification 
                                                            object:[self document] userInfo:@{SKPDFPageActionKey:SKPDFPageActionRotate, SKPDFPagePageKey:self}];
    }
}

- (NSData *)boundsAsQDRect {
    return [NSData dataWithRectAsQDRect:[self boundsForBox:kPDFDisplayBoxCropBox]];
}

- (void)setBoundsAsQDRect:(NSData *)inQDBoundsAsData {
    if ([self isEditable] && inQDBoundsAsData && [inQDBoundsAsData isEqual:[NSNull null]] == NO) {
        NSUndoManager *undoManager = [[self containingDocument] undoManager];
        [[undoManager prepareWithInvocationTarget:self] setBoundsAsQDRect:[self boundsAsQDRect]];
        [undoManager setActionName:NSLocalizedString(@"Crop Page", @"Undo action name")];
        // this will dirty the document, even though no saveable change has been made
        // but we cannot undo the document change count because there may be real changes to the document in the script
        
        NSRect newBounds = [inQDBoundsAsData rectValueAsQDRect];
        if (NSWidth(newBounds) < 0.0)
            newBounds.size.width = 0.0;
        if (NSHeight(newBounds) < 0.0)
            newBounds.size.height = 0.0;
        [self setBounds:newBounds forBox:kPDFDisplayBoxCropBox];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:SKPDFPageBoundsDidChangeNotification 
                                                            object:[self document] userInfo:@{SKPDFPageActionKey:SKPDFPageActionCrop, SKPDFPagePageKey:self}];
    }
}

- (NSData *)mediaBoundsAsQDRect {
    return [NSData dataWithRectAsQDRect:[self boundsForBox:kPDFDisplayBoxMediaBox]];
}

- (void)setMediaBoundsAsQDRect:(NSData *)inQDBoundsAsData {
    if ([self isEditable] && inQDBoundsAsData && [inQDBoundsAsData isEqual:[NSNull null]] == NO) {
        NSUndoManager *undoManager = [[self containingDocument] undoManager];
        [[undoManager prepareWithInvocationTarget:self] setMediaBoundsAsQDRect:[self mediaBoundsAsQDRect]];
        [undoManager setActionName:NSLocalizedString(@"Crop Page", @"Undo action name")];
        // this will dirty the document, even though no saveable change has been made
        // but we cannot undo the document change count because there may be real changes to the document in the script
        
        NSRect newBounds = [inQDBoundsAsData rectValueAsQDRect];
        if (NSWidth(newBounds) < 0.0)
            newBounds.size.width = 0.0;
        if (NSHeight(newBounds) < 0.0)
            newBounds.size.height = 0.0;
        [self setBounds:newBounds forBox:kPDFDisplayBoxMediaBox];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:SKPDFPageBoundsDidChangeNotification 
                                                            object:[self document] userInfo:@{SKPDFPageActionKey:SKPDFPageActionResize, SKPDFPagePageKey:self}];
    }
}

- (NSData *)contentBoundsAsQDRect {
    return [NSData dataWithRectAsQDRect:[self foregroundBox]];
}

- (NSArray *)lineBoundsAsQDRects {
    NSPointerArray *lineRects = [self lineRects];
    NSMutableArray *lineBounds = [NSMutableArray array];
    NSInteger i, count = [lineRects count];
    for (i = 0; i < count; i++)
        [lineBounds addObject:[NSData dataWithRectAsQDRect:[lineRects rectAtIndex:i]]];
    return lineBounds;
}

- (NSUInteger)countOfLines {
    return [[self lineRects] count];
}

- (SKLine *)objectInLinesAtIndex:(NSUInteger)anIndex {
    return [[[SKLine alloc] initWithPage:self index:anIndex] autorelease];
}

- (NSTextStorage *)richText {
    NSAttributedString *attrString = [self attributedString];
    return attrString ? [[[NSTextStorage alloc] initWithAttributedString:attrString] autorelease] : [[[NSTextStorage alloc] init] autorelease];
}

- (NSArray *)notes {
    NSArray *annotations = [self annotations];
    
    if ([[self document] allowsNotes] == NO) {
        PDFDocument *pdfDoc = [[self containingDocument] placeholderPdfDocument];
        NSUInteger pageIndex = [self pageIndex];
        annotations = pageIndex < [pdfDoc pageCount] ? [[pdfDoc pageAtIndex:pageIndex] annotations] : nil;
    }
    
    NSMutableArray *notes = [NSMutableArray array];

    for (PDFAnnotation *annotation in annotations) {
        if ([annotation isSkimNote])
            [notes addObject:annotation];
    }
    return notes;
}

- (id)valueInNotesWithUniqueID:(NSString *)aUniqueID {
    for (PDFAnnotation *annotation in [self notes]) {
        if ([[annotation uniqueID] isEqualToString:aUniqueID])
            return annotation;
    }
    return nil;
}

- (void)insertObject:(id)newNote inNotesAtIndex:(NSUInteger)anIndex {
    if ([self isEditable] && [[self document] allowsNotes]) {
        SKPDFView *pdfView = [(SKMainDocument *)[self containingDocument] pdfView];
        
        [pdfView addAnnotation:newNote toPage:self];
        [[pdfView undoManager] setActionName:NSLocalizedString(@"Add Note", @"Undo action name")];
    }
}

- (void)removeObjectFromNotesAtIndex:(NSUInteger)anIndex {
    if ([self isEditable] && [[self document] allowsNotes]) {
        PDFAnnotation *note = [[self notes] objectAtIndex:anIndex];
        SKPDFView *pdfView = [(SKMainDocument *)[self containingDocument] pdfView];
        
        [pdfView removeAnnotation:note];
        [[pdfView undoManager] setActionName:NSLocalizedString(@"Remove Note", @"Undo action name")];
    }
}

- (id)newScriptingObjectOfClass:(Class)class forValueForKey:(NSString *)key withContentsValue:(id)contentsValue properties:(NSDictionary *)properties {
    if ([key isEqualToString:@"notes"]) {
        
        PDFAnnotation *annotation = nil;
        NSMutableDictionary *props = [[properties mutableCopy] autorelease];
        NSString *type = [properties objectForKey:SKNPDFAnnotationTypeKey];
        [props removeObjectForKey:SKNPDFAnnotationTypeKey];
        if (type == nil && contentsValue)
            type = SKNHighlightString;
        if ([[self document] allowsNotes] == NO) {
            [[NSScriptCommand currentCommand] setScriptErrorNumber:NSReceiversCantHandleCommandScriptError];
            [[NSScriptCommand currentCommand] setScriptErrorString:@"PDF does not support notes."];
        } else if ([type isEqualToString:SKNHighlightString] || [type isEqualToString:SKNStrikeOutString] || [type isEqualToString:SKNUnderlineString ]) {
            id selSpec = contentsValue ?: [[[[NSScriptCommand currentCommand] arguments] objectForKey:@"KeyDictionary"] objectForKey:SKPDFAnnotationSelectionSpecifierKey];
            PDFSelection *selection = [selSpec isKindOfClass:[PDFSelection class]] ? selSpec : selSpec ? [PDFSelection selectionWithSpecifier:selSpec] : nil;
            [props removeObjectForKey:SKPDFAnnotationSelectionSpecifierKey];
            if (selSpec == nil) {
                [[NSScriptCommand currentCommand] setScriptErrorNumber:NSRequiredArgumentsMissingScriptError]; 
                [[NSScriptCommand currentCommand] setScriptErrorString:@"New markup notes need a selection."];
            } else if (selection) {
                annotation = [PDFAnnotation newSkimNoteWithSelection:selection forType:type];
                if ([props objectForKey:SKPDFAnnotationScriptingTextContentsKey] == nil)
                    [props setValue:[selection cleanedString] forKey:SKPDFAnnotationScriptingTextContentsKey];
            }
        } else if ([type isEqualToString:SKNInkString]) {
            NSArray *pointLists = [[[properties objectForKey:SKPDFAnnotationScriptingPointListsKey] retain] autorelease];
            [props removeObjectForKey:SKPDFAnnotationScriptingPointListsKey];
            if ([pointLists isKindOfClass:[NSArray class]] == NO) {
                [[NSScriptCommand currentCommand] setScriptErrorNumber:NSRequiredArgumentsMissingScriptError]; 
                [[NSScriptCommand currentCommand] setScriptErrorString:@"New freehand notes need a path list."];
            } else {
                NSMutableArray *paths = [[NSMutableArray alloc] initWithCapacity:[pointLists count]];
                for (NSArray *list in pointLists) {
                    if ([list isKindOfClass:[NSArray class]]) {
                        NSBezierPath *path = [[NSBezierPath alloc] init];
                        for (id pt in list) {
                            NSPoint point;
                            if ([pt isKindOfClass:[NSData class]]) {
                                point = [pt pointValueAsQDPoint];
                            } else if ([pt isKindOfClass:[NSArray class]] && [pt count] == 2) {
                                Point qdPoint;
                                qdPoint.v = [[pt objectAtIndex:0] intValue];
                                qdPoint.h = [[pt objectAtIndex:1] intValue];
                                point = SKNSPointFromQDPoint(qdPoint);
                            } else continue;
                            [PDFAnnotation addPoint:point toSkimNotesPath:path];
                        }
                        if ([path elementCount] > 1)
                            [paths addObject:path];
                        [path release];
                    }
                }
                annotation = [PDFAnnotation newSkimNoteWithPaths:paths];
                [paths release];
            }
        } else {
            NSRect bounds = NSZeroRect;
            bounds.size.width = [[NSUserDefaults standardUserDefaults] floatForKey:SKDefaultNoteWidthKey];
            bounds.size.height = [[NSUserDefaults standardUserDefaults] floatForKey:SKDefaultNoteHeightKey];
            if ([type isEqualToString:SKNNoteString])
                bounds.size = SKNPDFAnnotationNoteSize;
            bounds = NSIntegralRect(SKRectFromCenterAndSize(SKIntegralPoint(SKCenterPoint([self boundsForBox:kPDFDisplayBoxCropBox])), bounds.size));
            
            if ([[NSSet setWithObjects:SKNFreeTextString, SKNNoteString, SKNCircleString, SKNSquareString, SKNLineString, nil] containsObject:type]) {
                annotation = [PDFAnnotation newSkimNoteWithBounds:bounds forType:type];
            } else {
                [[NSScriptCommand currentCommand] setScriptErrorNumber:NSRequiredArgumentsMissingScriptError]; 
                [[NSScriptCommand currentCommand] setScriptErrorString:@"New notes need a type."];
            }
        }
        
        if (annotation) {
            [annotation registerUserName];
            if ([props count])
                [annotation setScriptingProperties:[annotation coerceValue:props forKey:@"scriptingProperties"]];
        }
        return annotation;
    }
    return [super newScriptingObjectOfClass:class forValueForKey:key withContentsValue:contentsValue properties:properties];
}

- (id)copyScriptingValue:(id)value forKey:(NSString *)key withProperties:(NSDictionary *)properties {
    if ([key isEqualToString:@"notes"]) {
        NSMutableArray *copiedValue = [[NSMutableArray alloc] init];
        for (PDFAnnotation *annotation in value) {
            if ([annotation isMovable]) {
                PDFAnnotation *copiedAnnotation = [[PDFAnnotation alloc] initSkimNoteWithProperties:[annotation SkimNoteProperties]];
                [copiedAnnotation registerUserName];
                if ([properties count])
                    [copiedAnnotation setScriptingProperties:[copiedAnnotation coerceValue:properties forKey:@"scriptingProperties"]];
                [copiedValue addObject:copiedAnnotation];
                [copiedAnnotation release];
            } else {
                // we don't want to duplicate markup
                NSScriptCommand *cmd = [NSScriptCommand currentCommand];
                [cmd setScriptErrorNumber:NSReceiversCantHandleCommandScriptError];
                [cmd setScriptErrorString:@"Cannot duplicate markup note."];
                SKDESTROY(copiedValue);
            }
        }
        return copiedValue;
    }
    return [super copyScriptingValue:value forKey:key withProperties:properties];
}

- (id)handleGrabScriptCommand:(NSScriptCommand *)command {
	NSDictionary *args = [command evaluatedArguments];
    NSData *boundsData = [args objectForKey:@"Bounds"];
    id asTIFFNumber = [args objectForKey:@"AsTIFF"];
    id asTypeNumber = [args objectForKey:@"Type"];
    NSRect bounds = [boundsData respondsToSelector:@selector(rectValueAsQDRect)] ? [boundsData rectValueAsQDRect] : NSZeroRect;
    FourCharCode asType = [asTypeNumber respondsToSelector:@selector(unsignedIntValue)] ? [asTypeNumber unsignedIntValue] : 0; 
    BOOL asTIFF = [asTIFFNumber respondsToSelector:@selector(boolValue)] ? [asTIFFNumber boolValue] : NO; 
    
    NSData *data = nil;
    DescType type = 0;
    
    if (asTIFF || asType == 'TIFF') {
        data = [self TIFFDataForRect:bounds];
        type = 'TIFF';
    } else {
        data = [self PDFDataForRect:bounds];
        type = 'PDF ';
    }
    
    return data ? [NSAppleEventDescriptor descriptorWithDescriptorType:type data:data] : nil;
}

@end
