//
//  SKBookmarkController.m
//  Skim
//
//  Created by Christiaan Hofman on 3/16/07.
/*
 This software is Copyright (c) 2007-2019
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

#import "SKBookmarkController.h"
#import "SKBookmark.h"
#import "SKAlias.h"
#import "SKTypeSelectHelper.h"
#import "SKStatusBar.h"
#import "SKToolbarItem.h"
#import "SKStringConstants.h"
#import "SKSeparatorView.h"
#import "NSMenu_SKExtensions.h"
#import "NSURL_SKExtensions.h"
#import "NSString_SKExtensions.h"
#import "NSEvent_SKExtensions.h"
#import "NSImage_SKExtensions.h"
#import "NSShadow_SKExtensions.h"
#import "NSView_SKExtensions.h"
#import "NSError_SKExtensions.h"
#import "SKDocumentController.h"

#define SKPasteboardTypeBookmarkRows @"net.sourceforge.skim-app.pasteboard.bookmarkrows"

#define SKBookmarksToolbarIdentifier                 @"SKBookmarksToolbarIdentifier"
#define SKBookmarksNewFolderToolbarItemIdentifier    @"SKBookmarksNewFolderToolbarItemIdentifier"
#define SKBookmarksNewSeparatorToolbarItemIdentifier @"SKBookmarksNewSeparatorToolbarItemIdentifier"
#define SKBookmarksDeleteToolbarItemIdentifier       @"SKBookmarksDeleteToolbarItemIdentifier"

#define SKBookmarksWindowFrameAutosaveName @"SKBookmarksWindow"

#define LABEL_COLUMNID @"label"
#define FILE_COLUMNID  @"file"
#define PAGE_COLUMNID  @"page"

#define SKMaximumDocumentPageHistoryCountKey @"SKMaximumDocumentPageHistoryCount"

#define BOOKMARKS_KEY       @"bookmarks"
#define RECENTDOCUMENTS_KEY @"recentDocuments"

#define PAGEINDEX_KEY @"pageIndex"
#define ALIAS_KEY     @"alias"
#define ALIASDATA_KEY @"_BDAlias"
#define SNAPSHOTS_KEY @"snapshots"

#define CHILDREN_KEY @"children"
#define LABEL_KEY    @"label"

static char SKBookmarkPropertiesObservationContext;

static NSString *SKBookmarksIdentifier = nil;

static NSArray *minimumCoverForBookmarks(NSArray *items);

@interface SKBookmarkController (SKPrivate)
- (void)setupToolbar;
- (void)handleApplicationWillTerminateNotification:(NSNotification *)notification;
- (void)endEditing;
- (void)startObservingBookmarks:(NSArray *)newBookmarks;
- (void)stopObservingBookmarks:(NSArray *)oldBookmarks;
@end

@interface SKBookmarkController ()
@property (nonatomic, readonly) NSUndoManager *undoManager;
@end

@implementation SKBookmarkController

@synthesize outlineView, statusBar, bookmarkRoot, previousSession, undoManager;

static SKBookmarkController *sharedBookmarkController = nil;

static NSUInteger maxRecentDocumentsCount = 0;

+ (void)initialize {
    SKINITIALIZE;
    
    maxRecentDocumentsCount = [[NSUserDefaults standardUserDefaults] integerForKey:SKMaximumDocumentPageHistoryCountKey];
    if (maxRecentDocumentsCount == 0)
        maxRecentDocumentsCount = 50;
    
    SKBookmarksIdentifier = [[[[NSBundle mainBundle] bundleIdentifier] stringByAppendingString:@".bookmarks"] retain];
}

+ (id)sharedBookmarkController {
    if (sharedBookmarkController == nil)
        [[[self alloc] init] release];
    return sharedBookmarkController;
}

+ (id)allocWithZone:(NSZone *)zone {
    return [sharedBookmarkController retain] ?: [super allocWithZone:zone];
}

- (id)init {
    if (sharedBookmarkController == nil) {
        self = [super initWithWindowNibName:@"BookmarksWindow"];
        if (self) {
            NSDictionary *bookmarkDictionary = [[NSUserDefaults standardUserDefaults] persistentDomainForName:SKBookmarksIdentifier];
            
            recentDocuments = [[NSMutableArray alloc] init];
            for (NSDictionary *info in [bookmarkDictionary objectForKey:RECENTDOCUMENTS_KEY]) {
                NSMutableDictionary *mutableInfo = [info mutableCopy];
                [recentDocuments addObject:mutableInfo];
                [mutableInfo release];
            }
            
            bookmarkRoot = [[SKBookmark alloc] initRootWithChildrenProperties:[bookmarkDictionary objectForKey:BOOKMARKS_KEY]];
            [self startObservingBookmarks:[NSArray arrayWithObject:bookmarkRoot]];
            
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(handleApplicationWillTerminateNotification:)
                                                         name:NSApplicationWillTerminateNotification
                                                       object:NSApp];
            
            NSArray *lastOpenFiles = [[NSUserDefaults standardUserDefaults] arrayForKey:SKLastOpenFileNamesKey];
            if ([lastOpenFiles count] > 0)
                previousSession = [[SKBookmark alloc] initSessionWithSetups:lastOpenFiles label:NSLocalizedString(@"Restore Previous Session", @"Menu item title")];
        }
        sharedBookmarkController = [self retain];
    } else if (self != sharedBookmarkController) {
        NSLog(@"Attempt to allocate second instance of %@", [self class]);
        [self release];
        self = [sharedBookmarkController retain];
    }
    return self;
}

- (void)dealloc {
    [self stopObservingBookmarks:[NSArray arrayWithObject:bookmarkRoot]];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    SKDESTROY(bookmarkRoot);
    SKDESTROY(previousSession);
    SKDESTROY(recentDocuments);
    SKDESTROY(draggedBookmarks);
    SKDESTROY(toolbarItems);
    SKDESTROY(outlineView);
    SKDESTROY(statusBar);
    [super dealloc];
}

- (void)windowDidLoad {
    [self setupToolbar];
    
    if ([[self window] respondsToSelector:@selector(setTabbingMode:)])
        [[self window] setTabbingMode:NSWindowTabbingModeDisallowed];
    
    [self setWindowFrameAutosaveName:SKBookmarksWindowFrameAutosaveName];
    
    [[self window] setAutorecalculatesContentBorderThickness:NO forEdge:NSMinYEdge];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:SKShowBookmarkStatusBarKey] == NO)
        [self toggleStatusBar:nil];
    else
        [[self window] setContentBorderThickness:22.0 forEdge:NSMinYEdge];
    
    if ([outlineView respondsToSelector:@selector(setStronglyReferencesItems:)])
        [outlineView setStronglyReferencesItems:YES];
    
    [outlineView setTypeSelectHelper:[SKTypeSelectHelper typeSelectHelper]];
    
    [outlineView registerForDraggedTypes:[NSArray arrayWithObjects:SKPasteboardTypeBookmarkRows, (NSString *)kUTTypeFileURL, NSFilenamesPboardType, nil]];
    
    [outlineView setDoubleAction:@selector(doubleClickBookmark:)];
    
    [outlineView setSupportsQuickLook:YES];
}

- (void)updateStatus {
    NSInteger row = [outlineView selectedRow];
    NSString *message = @"";
    if (row != -1) {
        SKBookmark *bookmark = [outlineView itemAtRow:row];
        if ([bookmark bookmarkType] == SKBookmarkTypeBookmark) {
            message = [[bookmark fileURL] path];
        } else if ([bookmark bookmarkType] == SKBookmarkTypeFolder) {
            NSInteger count = [bookmark countOfChildren];
            message = count == 1 ? NSLocalizedString(@"1 item", @"Bookmark folder description") : [NSString stringWithFormat:NSLocalizedString(@"%ld items", @"Bookmark folder description"), (long)count];
        }
    }
    [statusBar setLeftStringValue:message ?: @""];
}

#pragma mark Recent Documents

- (NSDictionary *)recentDocumentInfoAtURL:(NSURL *)fileURL {
    NSString *path = [fileURL path];
    for (NSMutableDictionary *info in recentDocuments) {
        SKAlias *alias = [info valueForKey:ALIAS_KEY];
        if (alias == nil) {
            alias = [SKAlias aliasWithData:[info valueForKey:ALIASDATA_KEY]];
            [info setValue:alias forKey:ALIAS_KEY];
        }
        if ([[[alias fileURLNoUI] path] isCaseInsensitiveEqual:path])
            return info;
    }
    return nil;
}

- (void)addRecentDocumentForURL:(NSURL *)fileURL pageIndex:(NSUInteger)pageIndex snapshots:(NSArray *)setups {
    if (fileURL == nil)
        return;
    
    NSDictionary *info = [self recentDocumentInfoAtURL:fileURL];
    if (info)
        [recentDocuments removeObjectIdenticalTo:info];
    
    SKAlias *alias = [SKAlias aliasWithURL:fileURL];
    if (alias) {
        NSMutableDictionary *bm = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithUnsignedInteger:pageIndex], PAGEINDEX_KEY, [alias data], ALIASDATA_KEY, alias, ALIAS_KEY, [setups count] ? setups : nil, SNAPSHOTS_KEY, nil];
        [recentDocuments insertObject:bm atIndex:0];
        if ([recentDocuments count] > maxRecentDocumentsCount)
            [recentDocuments removeLastObject];
    }
}

- (NSUInteger)pageIndexForRecentDocumentAtURL:(NSURL *)fileURL {
    if (fileURL == nil)
        return NSNotFound;
    NSNumber *pageIndex = [[self recentDocumentInfoAtURL:fileURL] objectForKey:PAGEINDEX_KEY];
    return pageIndex == nil ? NSNotFound : [pageIndex unsignedIntegerValue];
}

- (NSArray *)snapshotsForRecentDocumentAtURL:(NSURL *)fileURL {
    if (fileURL == nil)
        return nil;
    NSArray *setups = [[self recentDocumentInfoAtURL:fileURL] objectForKey:SNAPSHOTS_KEY];
    return [setups count] ? setups : nil;
}

#pragma mark Bookmarks support

- (SKBookmark *)bookmarkForURL:(NSURL *)bookmarkURL {
    SKBookmark *bookmark = nil;
    if ([bookmarkURL isSkimBookmarkURL]) {
        bookmark = [self bookmarkRoot];
        NSArray *components = [[[bookmarkURL absoluteString] substringFromIndex:17] componentsSeparatedByString:@"/"];
        for (NSString *component in components) {
            if ([component length] == 0)
                continue;
            component = [component stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            NSArray *children = [bookmark children];
            bookmark = nil;
            for (SKBookmark *child in children) {
                if ([[child label] isEqualToString:component]) {
                    bookmark = child;
                    break;
                }
                if (bookmark == nil && [[child label] caseInsensitiveCompare:component] == NSOrderedSame)
                    bookmark = child;
            }
            if (bookmark == nil)
                break;
        }
        if (bookmark == nil && [components count] == 1) {
            NSArray *allBookmarks = [bookmarkRoot entireContents];
            NSArray *names = [allBookmarks valueForKey:@"label"];
            NSString *name = [components lastObject];
            NSUInteger i = [names indexOfObject:name];
            if (i != NSNotFound) {
                bookmark = [allBookmarks objectAtIndex:i];
            } else {
                i = [[names valueForKey:@"lowercaseString"] indexOfObject:[name lowercaseString]];
                if (i != NSNotFound)
                    bookmark = [allBookmarks objectAtIndex:i];
            }
        }
    }
    return bookmark;
}

#define OV_ITEM(parent) (parent == bookmarkRoot ? nil : parent)

- (void)insertBookmarks:(NSArray *)newBookmarks atIndexes:(NSIndexSet *)indexes ofBookmark:(SKBookmark *)parent partial:(BOOL)isPartial {
    if (isPartial == NO)
        [outlineView beginUpdates];
    [outlineView insertItemsAtIndexes:indexes inParent:OV_ITEM(parent) withAnimation:NSTableViewAnimationEffectGap | NSTableViewAnimationSlideDown];
    [[parent mutableArrayValueForKey:CHILDREN_KEY] insertObjects:newBookmarks atIndexes:indexes];
    if (isPartial == NO)
        [outlineView endUpdates];
}

- (void)removeBookmarksAtIndexes:(NSIndexSet *)indexes ofBookmark:(SKBookmark *)parent partial:(BOOL)isPartial {
    if (isPartial == NO)
        [outlineView beginUpdates];
    [outlineView removeItemsAtIndexes:indexes inParent:OV_ITEM(parent) withAnimation:NSTableViewAnimationEffectGap | NSTableViewAnimationSlideUp];
    [[parent mutableArrayValueForKey:CHILDREN_KEY] removeObjectsAtIndexes:indexes];
    if (isPartial == NO)
        [outlineView endUpdates];
}

- (void)replaceBookmarksAtIndexes:(NSIndexSet *)indexes withBookmarks:(NSArray *)newBookmarks ofBookmark:(SKBookmark *)parent partial:(BOOL)isPartial {
    if (isPartial == NO)
        [outlineView beginUpdates];
    [outlineView removeItemsAtIndexes:indexes inParent:OV_ITEM(parent) withAnimation:NSTableViewAnimationEffectGap | NSTableViewAnimationSlideUp];
    [outlineView insertItemsAtIndexes:indexes inParent:OV_ITEM(parent) withAnimation:NSTableViewAnimationEffectGap | NSTableViewAnimationSlideDown];
    [[parent mutableArrayValueForKey:CHILDREN_KEY] replaceObjectsAtIndexes:indexes withObjects:newBookmarks];
    if (isPartial == NO)
        [outlineView endUpdates];
}

- (void)moveBookmarkAtIndex:(NSUInteger)fromIndex ofBookmark:(SKBookmark *)fromParent toIndex:(NSUInteger)toIndex ofBookmark:(SKBookmark *)toParent partial:(BOOL)isPartial {
    if (isPartial == NO)
        [outlineView beginUpdates];
    [outlineView moveItemAtIndex:fromIndex inParent:OV_ITEM(fromParent) toIndex:toIndex inParent:OV_ITEM(toParent)];
    SKBookmark *bookmark = [[fromParent objectInChildrenAtIndex:fromIndex] retain];
    [fromParent removeObjectFromChildrenAtIndex:fromIndex];
    [toParent insertObject:bookmark inChildrenAtIndex:toIndex];
    [bookmark release];
    if (isPartial == NO)
        [outlineView endUpdates];
}

- (void)getInsertionFolder:(SKBookmark **)bookmarkPtr childIndex:(NSUInteger *)indexPtr {
    NSInteger rowIndex = [outlineView clickedRow];
    NSIndexSet *indexes = [outlineView selectedRowIndexes];
    if (rowIndex != -1 && [indexes containsIndex:rowIndex] == NO)
        indexes = [NSIndexSet indexSetWithIndex:rowIndex];
    rowIndex = [indexes lastIndex];
    
    SKBookmark *item = bookmarkRoot;
    NSUInteger idx = [bookmarkRoot countOfChildren];
    
    if (rowIndex != NSNotFound) {
        SKBookmark *selectedItem = [outlineView itemAtRow:rowIndex];
        if ([outlineView isItemExpanded:selectedItem]) {
            item = selectedItem;
            idx = [item countOfChildren];
        } else {
            item = [selectedItem parent];
            idx = [[item children] indexOfObject:selectedItem] + 1;
        }
    }
    
    *bookmarkPtr = item;
    *indexPtr = idx;
}

- (IBAction)openBookmark:(id)sender {
    [[NSDocumentController sharedDocumentController] openDocumentWithBookmark:[sender representedObject] completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error){
        if (document == nil && error && [error isUserCancelledError] == NO)
            [NSApp presentError:error];
    }];
}

- (IBAction)doubleClickBookmark:(id)sender {
    NSInteger row = [outlineView clickedRow];
    SKBookmark *bm = row == -1 ? nil : [outlineView itemAtRow:row];
    if (bm && ([bm bookmarkType] == SKBookmarkTypeBookmark || [bm bookmarkType] == SKBookmarkTypeSession)) {
        [[NSDocumentController sharedDocumentController] openDocumentWithBookmark:bm completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error){
            if (document == nil && error && [error isUserCancelledError] == NO)
                [NSApp presentError:error];
        }];
    }
}

- (IBAction)insertBookmarkFolder:(id)sender {
    SKBookmark *folder = [SKBookmark bookmarkFolderWithLabel:NSLocalizedString(@"Folder", @"default folder name")];
    SKBookmark *item = nil;
    NSUInteger idx = 0;
    
    [self getInsertionFolder:&item childIndex:&idx];
    [self insertBookmarks:[NSArray arrayWithObjects:folder, nil] atIndexes:[NSIndexSet indexSetWithIndex:idx] ofBookmark:item partial:NO];
    
    NSInteger row = [outlineView rowForItem:folder];
    [outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [outlineView editColumn:0 row:row withEvent:nil select:YES];
}

- (IBAction)insertBookmarkSeparator:(id)sender {
    SKBookmark *separator = [SKBookmark bookmarkSeparator];
    SKBookmark *item = nil;
    NSUInteger idx = 0;
    
    [self getInsertionFolder:&item childIndex:&idx];
    [self insertBookmarks:[NSArray arrayWithObjects:separator, nil] atIndexes:[NSIndexSet indexSetWithIndex:idx] ofBookmark:item partial:NO];
    
    NSInteger row = [outlineView rowForItem:separator];
    [outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
}

- (IBAction)addBookmark:(id)sender {
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    NSMutableArray *types = [NSMutableArray array];
    for (NSString *docClass in [[NSDocumentController sharedDocumentController] documentClassNames])
        [types addObjectsFromArray:[NSClassFromString(docClass) readableTypes]];
    [openPanel setAllowsMultipleSelection:YES];
    [openPanel setCanChooseDirectories:YES];
    [openPanel setAllowedFileTypes:types];
    [openPanel beginSheetModalForWindow:[self window] completionHandler:^(NSInteger result){
            if (result == NSFileHandlingPanelOKButton) {
                NSArray *newBookmarks = [SKBookmark bookmarksForURLs:[openPanel URLs]];
                if ([newBookmarks count] > 0) {
                    SKBookmark *item = nil;
                    NSUInteger anIndex = 0;
                    [self getInsertionFolder:&item childIndex:&anIndex];
                    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(anIndex, [newBookmarks count])];
                    [self insertBookmarks:newBookmarks atIndexes:indexes ofBookmark:item partial:NO];
                    if (item == bookmarkRoot || [outlineView isItemExpanded:item]) {
                        if (item != bookmarkRoot)
                            [indexes shiftIndexesStartingAtIndex:0 by:[outlineView rowForItem:item] + 1];
                        [outlineView selectRowIndexes:indexes byExtendingSelection:NO];
                    }
                }
            }
        }];
}

- (IBAction)deleteBookmark:(id)sender {
    [outlineView delete:sender];
}

- (IBAction)toggleStatusBar:(id)sender {
    [[NSUserDefaults standardUserDefaults] setBool:(NO == [statusBar isVisible]) forKey:SKShowBookmarkStatusBarKey];
    [statusBar toggleBelowView:[outlineView enclosingScrollView] animate:sender != nil];
}

- (NSArray *)clickedBookmarks {
    NSArray *items = nil;
    NSInteger row = [outlineView clickedRow];
    if (row != -1) {
        NSIndexSet *indexes = [outlineView selectedRowIndexes];
        if ([indexes containsIndex:row] == NO)
            indexes = [NSIndexSet indexSetWithIndex:row];
        items = [outlineView itemsAtRowIndexes:indexes];
    }
    return items;
}

- (IBAction)deleteBookmarks:(id)sender {
    NSArray *items = minimumCoverForBookmarks([self clickedBookmarks]);
    [self endEditing];
    for (SKBookmark *item in [items reverseObjectEnumerator]) {
        SKBookmark *parent = [item parent];
        NSUInteger itemIndex = [[parent children] indexOfObject:item];
        if (itemIndex != NSNotFound)
            [parent removeObjectFromChildrenAtIndex:itemIndex];
    }
}

- (IBAction)openBookmarks:(id)sender {
    NSArray *allBookmarks = minimumCoverForBookmarks([self clickedBookmarks]);
    if ([allBookmarks count] == 1) {
        [[NSDocumentController sharedDocumentController] openDocumentWithBookmark:[allBookmarks firstObject] completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error){
            if (document == nil && error && [error isUserCancelledError] == NO)
                [NSApp presentError:error];
        }];
    } else if ([allBookmarks count] > 1) {
        allBookmarks = [allBookmarks valueForKeyPath:@"@unionOfArrays.containingBookmarks"];
        [[NSDocumentController sharedDocumentController] openDocumentWithBookmarks:allBookmarks completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error){
            if (document == nil && error && [error isUserCancelledError] == NO)
                [NSApp presentError:error];
        }];
    }
}

- (IBAction)previewBookmarks:(id)sender {
    if ([QLPreviewPanel sharedPreviewPanelExists] && [[QLPreviewPanel sharedPreviewPanel] isVisible]) {
        [[QLPreviewPanel sharedPreviewPanel] orderOut:nil];
    } else {
        NSInteger row = [outlineView clickedRow];
        [outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        [[QLPreviewPanel sharedPreviewPanel] makeKeyAndOrderFront:nil];
    }
}

- (IBAction)copyURL:(id)sender {
    NSArray *selectedBookmarks = minimumCoverForBookmarks([outlineView selectedItems]);
    NSMutableArray *skimURLs = [NSMutableArray array];
    for (SKBookmark *bookmark in selectedBookmarks) {
        NSURL *skimURL = [bookmark skimURL];
        if (skimURL)
            [skimURLs addObject:skimURL];
    }
    if ([skimURLs count]) {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        [pboard clearContents];
        [pboard writeObjects:skimURLs];
    } else {
        NSBeep();
    }
}

#pragma mark NSMenu delegate methods

- (void)addItemForBookmark:(SKBookmark *)bookmark toMenu:(NSMenu *)menu isFolder:(BOOL)isFolder isAlternate:(BOOL)isAlternate {
    NSMenuItem *item = nil;
    if (isFolder) {
        item = [menu addItemWithSubmenuAndTitle:[bookmark label]];
        [[item submenu] setDelegate:self];
    } else {
        item = [menu addItemWithTitle:[bookmark label] action:@selector(openBookmark:) target:self];
    }
    [item setRepresentedObject:bookmark];
    if (isAlternate) {
        [item setKeyEquivalentModifierMask:NSAlternateKeyMask];
        [item setAlternate:YES];
        [item setImageAndSize:[bookmark alternateIcon]];
    } else {
        [item setImageAndSize:[bookmark icon]];
    }
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu == [outlineView menu]) {
        NSInteger row = [outlineView clickedRow];
        [menu removeAllItems];
        if (row != -1) {
            [menu addItemWithTitle:NSLocalizedString(@"Remove", @"Menu item title") action:@selector(deleteBookmarks:) target:self];
            [menu addItemWithTitle:NSLocalizedString(@"Open", @"Menu item title") action:@selector(openBookmarks:) target:self];
            [menu addItemWithTitle:NSLocalizedString(@"Quick Look", @"Menu item title") action:@selector(previewBookmarks:) target:self];
            [menu addItem:[NSMenuItem separatorItem]];
        }
        [menu addItemWithTitle:NSLocalizedString(@"New Folder", @"Menu item title") action:@selector(insertBookmarkFolder:) target:self];
        [menu addItemWithTitle:NSLocalizedString(@"New Separator", @"Menu item title") action:@selector(insertBookmarkSeparator:) target:self];
    } else {
        NSMenu *supermenu = [menu supermenu];
        NSInteger idx = [supermenu indexOfItemWithSubmenu:menu]; 
        SKBookmark *bm = nil;
        
        if (supermenu == [NSApp mainMenu])
            bm = [self bookmarkRoot];
        else if (idx >= 0)
            bm = [[supermenu itemAtIndex:idx] representedObject];
        
        if ([bm isKindOfClass:[SKBookmark class]]) {
            NSArray *bookmarks = [bm children];
            NSInteger i = [menu numberOfItems];
            while (i-- > 0 && ([[menu itemAtIndex:i] isSeparatorItem] || [[menu itemAtIndex:i] representedObject]))
                [menu removeItemAtIndex:i];
            if (supermenu == [NSApp mainMenu] && previousSession) {
                [menu addItem:[NSMenuItem separatorItem]];
                [self addItemForBookmark:previousSession toMenu:menu isFolder:NO isAlternate:NO];
                [self addItemForBookmark:previousSession toMenu:menu isFolder:YES isAlternate:YES];
            }
            if ([menu numberOfItems] > 0 && [bookmarks count] > 0)
                [menu addItem:[NSMenuItem separatorItem]];
            for (bm in bookmarks) {
                switch ([bm bookmarkType]) {
                    case SKBookmarkTypeFolder:
                        [self addItemForBookmark:bm toMenu:menu isFolder:YES isAlternate:NO];
                        [self addItemForBookmark:bm toMenu:menu isFolder:NO isAlternate:YES];
                        break;
                    case SKBookmarkTypeSession:
                        [self addItemForBookmark:bm toMenu:menu isFolder:NO isAlternate:NO];
                        [self addItemForBookmark:bm toMenu:menu isFolder:YES isAlternate:YES];
                        break;
                    case SKBookmarkTypeSeparator:
                        [menu addItem:[NSMenuItem separatorItem]];
                        break;
                    default:
                        [self addItemForBookmark:bm toMenu:menu isFolder:NO isAlternate:NO];
                        break;
                }
            }
        }
    }
}

// avoid rebuilding the bookmarks menu on every key event
- (BOOL)menuHasKeyEquivalent:(NSMenu *)menu forEvent:(NSEvent *)event target:(id *)target action:(SEL *)action { return NO; }

#pragma mark Undo support

- (NSUndoManager *)undoManager {
    if(undoManager == nil)
        undoManager = [[NSUndoManager alloc] init];
    return undoManager;
}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)sender {
    return [self undoManager];
}

- (void)startObservingBookmarks:(NSArray *)newBookmarks {
    for (SKBookmark *bm in newBookmarks) {
        if ([bm bookmarkType] != SKBookmarkTypeSeparator) {
            [bm addObserver:self forKeyPath:LABEL_KEY options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:&SKBookmarkPropertiesObservationContext];
            [bm addObserver:self forKeyPath:PAGEINDEX_KEY options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:&SKBookmarkPropertiesObservationContext];
            if ([bm bookmarkType] == SKBookmarkTypeFolder) {
                [bm addObserver:self forKeyPath:CHILDREN_KEY options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:&SKBookmarkPropertiesObservationContext];
                [self startObservingBookmarks:[bm children]];
            }
        }
    }
}

- (void)stopObservingBookmarks:(NSArray *)oldBookmarks {
    for (SKBookmark *bm in oldBookmarks) {
        if ([bm bookmarkType] != SKBookmarkTypeSeparator) {
            [bm removeObserver:self forKeyPath:LABEL_KEY];
            [bm removeObserver:self forKeyPath:PAGEINDEX_KEY];
            if ([bm bookmarkType] == SKBookmarkTypeFolder) {
                [bm removeObserver:self forKeyPath:CHILDREN_KEY];
                [self stopObservingBookmarks:[bm children]];
            }
        }
    }
}

- (void)setBookmarks:(NSArray *)newChildren atIndexes:(NSIndexSet *)indexes ofBookmark:(SKBookmark *)bookmark {
    NSIndexSet *removeIndexes = indexes;
    if (removeIndexes == nil)
        removeIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [bookmark countOfChildren])];
    NSIndexSet *insertIndexes = indexes;
    if (insertIndexes == nil)
        insertIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [newChildren count])];
    [outlineView beginUpdates];
    if ([removeIndexes count] > 0)
        [self removeBookmarksAtIndexes:removeIndexes ofBookmark:bookmark partial:YES];
    if ([insertIndexes count] > 0)
        [self insertBookmarks:newChildren atIndexes:insertIndexes ofBookmark:bookmark partial:YES];
    if (indexes)
        [[bookmark mutableArrayValueForKey:CHILDREN_KEY] replaceObjectsAtIndexes:indexes withObjects:newChildren];
    else
        [[bookmark mutableArrayValueForKey:CHILDREN_KEY] setArray:newChildren];
    [outlineView endUpdates];
}

#pragma mark KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &SKBookmarkPropertiesObservationContext) {
        SKBookmark *bookmark = (SKBookmark *)object;
        id newValue = [change objectForKey:NSKeyValueChangeNewKey];
        id oldValue = [change objectForKey:NSKeyValueChangeOldKey];
        BOOL changed = NO;
        NSIndexSet *indexes = [[[change objectForKey:NSKeyValueChangeIndexesKey] copy] autorelease];
        
        if ([newValue isEqual:[NSNull null]]) newValue = nil;
        if ([oldValue isEqual:[NSNull null]]) oldValue = nil;
        changed = (oldValue || newValue) && [newValue isEqual:oldValue] == NO;
        
        switch ([[change objectForKey:NSKeyValueChangeKindKey] unsignedIntegerValue]) {
            case NSKeyValueChangeSetting:
                if (changed == NO) break;
                if ([keyPath isEqualToString:CHILDREN_KEY]) {
                    NSMutableArray *old = [NSMutableArray arrayWithArray:oldValue];
                    NSMutableArray *new = [NSMutableArray arrayWithArray:newValue];
                    [old removeObjectsInArray:newValue];
                    [new removeObjectsInArray:oldValue];
                    [self stopObservingBookmarks:old];
                    [self startObservingBookmarks:new];
                    [[[self undoManager] prepareWithInvocationTarget:self] setBookmarks:[[oldValue copy] autorelease] atIndexes:nil ofBookmark:bookmark];
                } else if ([keyPath isEqualToString:LABEL_KEY]) {
                    [[[self undoManager] prepareWithInvocationTarget:bookmark] setLabel:oldValue];
                    [outlineView reloadTypeSelectStrings];
                } else if ([keyPath isEqualToString:PAGEINDEX_KEY]) {
                    [[[self undoManager] prepareWithInvocationTarget:bookmark] setPageIndex:[oldValue unsignedIntegerValue]];
                }
                break;
            case NSKeyValueChangeInsertion:
                if ([newValue count] == 0) break;
                if ([keyPath isEqualToString:CHILDREN_KEY]) {
                    [self startObservingBookmarks:newValue];
                    [[[self undoManager] prepareWithInvocationTarget:self] removeBookmarksAtIndexes:indexes ofBookmark:bookmark partial:NO];
                }
                break;
            case NSKeyValueChangeRemoval:
                if ([oldValue count] == 0) break;
                if ([keyPath isEqualToString:CHILDREN_KEY]) {
                    [self stopObservingBookmarks:oldValue];
                    [[[self undoManager] prepareWithInvocationTarget:self] insertBookmarks:[[oldValue copy] autorelease] atIndexes:indexes ofBookmark:bookmark partial:NO];
                }
                break;
            case NSKeyValueChangeReplacement:
                if ([newValue count] == 0 && [oldValue count] == 0) break;
                if ([keyPath isEqualToString:CHILDREN_KEY]) {
                    [self stopObservingBookmarks:oldValue];
                    [self startObservingBookmarks:newValue];
                    [[[self undoManager] prepareWithInvocationTarget:self] setBookmarks:[[oldValue copy] autorelease] atIndexes:indexes ofBookmark:bookmark];
                }
                break;
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark Notification handlers

- (void)handleApplicationWillTerminateNotification:(NSNotification *)notification  {
    [recentDocuments makeObjectsPerformSelector:@selector(removeObjectForKey:) withObject:ALIAS_KEY];
    NSDictionary *bookmarksDictionary = [NSDictionary dictionaryWithObjectsAndKeys:[[bookmarkRoot children] valueForKey:@"properties"], BOOKMARKS_KEY, recentDocuments, RECENTDOCUMENTS_KEY, nil];
    [[NSUserDefaults standardUserDefaults] setPersistentDomain:bookmarksDictionary forName:SKBookmarksIdentifier];
}

- (void)endEditing {
    if ([outlineView editedRow] && [[self window] makeFirstResponder:outlineView] == NO)
        [[self window] endEditingFor:nil];
}

#pragma mark NSOutlineView datasource methods

static NSArray *minimumCoverForBookmarks(NSArray *items) {
    SKBookmark *lastBm = nil;
    NSMutableArray *minimalCover = [NSMutableArray array];
    
    for (SKBookmark *bm in items) {
        if ([bm isDescendantOf:lastBm] == NO) {
            [minimalCover addObject:bm];
            lastBm = bm;
        }
    }
    return minimalCover;
}

- (NSInteger)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item {
    if (item == nil) item = bookmarkRoot;
    return [item bookmarkType] == SKBookmarkTypeFolder ? [item countOfChildren] : 0;
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item {
    return [item bookmarkType] == SKBookmarkTypeFolder;
}

- (id)outlineView:(NSOutlineView *)ov child:(NSInteger)anIndex ofItem:(id)item {
    return [(item ?: bookmarkRoot) objectInChildrenAtIndex:anIndex];
}

- (id)outlineView:(NSOutlineView *)ov objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    return item;
}

- (id<NSPasteboardWriting>)outlineView:(NSOutlineView *)ov pasteboardWriterForItem:(id)item {
    NSPasteboardItem *pbItem = [[[NSPasteboardItem alloc] init] autorelease];
    [pbItem setData:[NSData data] forType:SKPasteboardTypeBookmarkRows];
    return pbItem;
}

- (void)outlineView:(NSOutlineView *)ov draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint forItems:(NSArray *)draggedItems {
    SKDESTROY(draggedBookmarks);
    draggedBookmarks = [minimumCoverForBookmarks(draggedItems) retain];
}

- (void)outlineView:(NSOutlineView *)outlineView draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
    SKDESTROY(draggedBookmarks);
}

- (void)outlineView:(NSOutlineView *)ov updateDraggingItemsForDrag:(id<NSDraggingInfo>)draggingInfo {
    if ([draggingInfo draggingSource] != ov) {
        NSArray *classes = [NSArray arrayWithObjects:[NSURL class], nil];
        NSDictionary *searchOptions = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithBool:YES], NSPasteboardURLReadingFileURLsOnlyKey, nil];
        NSTableColumn *tableColumn = [ov outlineTableColumn];
        NSTableCellView *view = [ov makeViewWithIdentifier:[tableColumn identifier] owner:self];
        __block NSInteger validCount = 0;
        [view setFrame:NSMakeRect(0.0, 0.0, [tableColumn width] - 16.0, [ov rowHeight])];
        
        [draggingInfo enumerateDraggingItemsWithOptions:0 forView:ov classes:classes searchOptions:searchOptions usingBlock:^(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop){
            if ([[draggingItem item] isKindOfClass:[NSURL class]] && [[draggingItem item] isFileURL]) {
                SKBookmark *bookmark = [[SKBookmark bookmarksForURLs:[NSArray arrayWithObjects:[draggingItem item], nil]] firstObject];
                [draggingItem setImageComponentsProvider:^{
                    [view setObjectValue:bookmark];
                    return [view draggingImageComponents];
                }];
                validCount++;
            } else {
                [draggingItem setImageComponentsProvider:nil];
            }
        }];
        [draggingInfo setNumberOfValidItemsForDrop:validCount];
    }
}

- (NSDragOperation)outlineView:(NSOutlineView *)ov validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)anIndex {
    NSDragOperation dragOp = NSDragOperationNone;
    if (anIndex != NSOutlineViewDropOnItemIndex) {
        NSPasteboard *pboard = [info draggingPasteboard];
        if ([pboard canReadItemWithDataConformingToTypes:[NSArray arrayWithObjects:SKPasteboardTypeBookmarkRows, nil]] &&
            [info draggingSource] == ov)
            dragOp = NSDragOperationMove;
        else if ([NSURL canReadFileURLFromPasteboard:pboard])
            dragOp = NSDragOperationEvery;
    }
    return dragOp;
}

- (BOOL)outlineView:(NSOutlineView *)ov acceptDrop:(id <NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)anIndex {
    NSPasteboard *pboard = [info draggingPasteboard];
    
    if ([pboard canReadItemWithDataConformingToTypes:[NSArray arrayWithObjects:SKPasteboardTypeBookmarkRows, nil]] &&
        [info draggingSource] == ov) {
        NSMutableArray *movedBookmarks = [NSMutableArray array];
        NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
        
        if (item == nil) item = bookmarkRoot;
        
        [self endEditing];
        [ov beginUpdates];
		for (SKBookmark *bookmark in draggedBookmarks) {
            SKBookmark *parent = [bookmark parent];
            NSInteger bookmarkIndex = [[parent children] indexOfObject:bookmark];
            if (item == parent) {
                if (anIndex > bookmarkIndex)
                    anIndex--;
                if (anIndex == bookmarkIndex)
                    continue;
            }
            [self moveBookmarkAtIndex:bookmarkIndex ofBookmark:parent toIndex:anIndex ofBookmark:item partial:YES];
            [movedBookmarks addObject:bookmark];
		}
        [ov endUpdates];
        
        for (SKBookmark *bookmark in movedBookmarks) {
            NSInteger row = [outlineView rowForItem:bookmark];
            if (row != -1)
                [indexes addIndex:row];
        }
        if ([indexes count])
            [outlineView selectRowIndexes:indexes byExtendingSelection:NO];
        
        return YES;
    } else {
        NSArray *urls = [NSURL readFileURLsFromPasteboard:pboard];
        NSArray *newBookmarks = [SKBookmark bookmarksForURLs:urls];
        if ([newBookmarks count] > 0) {
            if (item == nil) item = bookmarkRoot;
            [self endEditing];
            NSMutableIndexSet *indexes = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(anIndex, [newBookmarks count])];
            [self insertBookmarks:newBookmarks atIndexes:indexes ofBookmark:item partial:NO];
            if (item == bookmarkRoot || [outlineView isItemExpanded:item]) {
                if (item == bookmarkRoot)
                    [indexes shiftIndexesStartingAtIndex:0 by:[outlineView rowForItem:item] + 1];
                [outlineView selectRowIndexes:indexes byExtendingSelection:NO];
            }
            return YES;
        }
        return NO;
    }
    return NO;
}

#pragma mark NSOutlineView delegate methods

- (NSView *)outlineView:(NSOutlineView *)ov viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    if ([item bookmarkType] == SKBookmarkTypeSeparator)
        return nil;
    
    NSString *tcID = [tableColumn identifier];
    NSTableCellView *view = [ov makeViewWithIdentifier:tcID owner:self];
    if ([tcID isEqualToString:FILE_COLUMNID]) {
        if ([item bookmarkType] == SKBookmarkTypeBookmark)
            [[view textField] setTextColor:[NSColor controlTextColor]];
        else
            [[view textField] setTextColor:[NSColor disabledControlTextColor]];
    }
    return view;
}

- (NSTableRowView *)outlineView:(NSOutlineView *)ov rowViewForItem:(id)item {
    if ([item bookmarkType] == SKBookmarkTypeSeparator) {
        SKSeparatorView *view = [ov makeViewWithIdentifier:@"separator" owner:self];
        [view setIndentation:16.0 + [ov levelForItem:item] * [ov indentationPerLevel]];
        return view;
    }
    return nil;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    [self updateStatus];
    if ([QLPreviewPanel sharedPreviewPanelExists] && [[QLPreviewPanel sharedPreviewPanel] isVisible] && [[QLPreviewPanel sharedPreviewPanel] dataSource] == self)
        [[QLPreviewPanel sharedPreviewPanel] reloadData];
}

- (void)outlineView:(NSOutlineView *)ov deleteItems:(NSArray *)items {
    [self endEditing];
    [ov beginUpdates];
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    SKBookmark *parent = nil;
    for (SKBookmark *item in [minimumCoverForBookmarks(items) reverseObjectEnumerator]) {
        SKBookmark *itemParent = [item parent];
        NSUInteger itemIndex = [[parent children] indexOfObject:item];
        if (itemIndex != NSNotFound) {
            if (itemParent != parent) {
                if (parent && [indexes count])
                    [self removeBookmarksAtIndexes:indexes ofBookmark:parent partial:YES];
                parent = itemParent;
                [indexes removeAllIndexes];
            }
            [indexes addIndex:itemIndex];
        }
    }
    if (parent && [indexes count])
        [self removeBookmarksAtIndexes:indexes ofBookmark:parent partial:YES];
    [ov endUpdates];
}

- (BOOL)outlineView:(NSOutlineView *)ov canDeleteItems:(NSArray *)items {
    return [items count] > 0;
}

static void addBookmarkURLsToArray(NSArray *items, NSMutableArray *array) {
    for (SKBookmark *bm in items) {
        if ([bm bookmarkType] == SKBookmarkTypeBookmark) {
            NSURL *url = [bm fileURL];
            if (url)
                [array addObject:url];
        } else if ([bm bookmarkType] != SKBookmarkTypeSeparator) {
            addBookmarkURLsToArray([bm children], array);
        }
    }
}

- (void)outlineView:(NSOutlineView *)ov copyItems:(NSArray *)items {
    NSMutableArray *urls = [NSMutableArray array];
    addBookmarkURLsToArray(minimumCoverForBookmarks(items), urls);
    if ([urls count] > 0) {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        [pboard clearContents];
        [pboard writeObjects:urls];
    } else {
        NSBeep();
    }
}

- (BOOL)outlineView:(NSOutlineView *)ov canCopyItems:(NSArray *)items {
    return [items count] > 0;
}

- (void)outlineView:(NSOutlineView *)ov pasteFromPasteboard:(NSPasteboard *)pboard {
    NSArray *urls = [NSURL readFileURLsFromPasteboard:pboard];
    if ([urls count] > 0) {
        NSArray *newBookmarks = [SKBookmark bookmarksForURLs:urls];
        if ([newBookmarks count] > 0) {
            SKBookmark *item = nil;
            NSUInteger anIndex = 0;
            [self getInsertionFolder:&item childIndex:&anIndex];
            NSMutableIndexSet *indexes = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(anIndex, [newBookmarks count])];
            [self insertBookmarks:newBookmarks atIndexes:indexes ofBookmark:item partial:NO];
            if (item == bookmarkRoot || [outlineView isItemExpanded:item]) {
                if (item != bookmarkRoot)
                    [indexes shiftIndexesStartingAtIndex:0 by:[outlineView rowForItem:item] + 1];
                [outlineView selectRowIndexes:indexes byExtendingSelection:NO];
            }
        } else NSBeep();
    } else NSBeep();
}

- (BOOL)outlineView:(NSOutlineView *)ov canPasteFromPasteboard:(NSPasteboard *)pboard {
    return [NSURL canReadFileURLFromPasteboard:pboard];
}

- (NSArray *)outlineView:(NSOutlineView *)ov typeSelectHelperSelectionStrings:(SKTypeSelectHelper *)typeSelectHelper {
    NSInteger i, count = [outlineView numberOfRows];
    NSMutableArray *labels = [NSMutableArray arrayWithCapacity:count];
    for (i = 0; i < count; i++) {
        NSString *label = [[outlineView itemAtRow:i] label];
        [labels addObject:label ?: @""];
    }
    return labels;
}

- (void)outlineView:(NSOutlineView *)ov typeSelectHelper:(SKTypeSelectHelper *)typeSelectHelper didFailToFindMatchForSearchString:(NSString *)searchString {
    [statusBar setLeftStringValue:[NSString stringWithFormat:NSLocalizedString(@"No match: \"%@\"", @"Status message"), searchString]];
}

- (void)outlineView:(NSOutlineView *)ov typeSelectHelper:(SKTypeSelectHelper *)typeSelectHelper updateSearchString:(NSString *)searchString {
    if (searchString)
        [statusBar setLeftStringValue:[NSString stringWithFormat:NSLocalizedString(@"Finding: \"%@\"", @"Status message"), searchString]];
    else
        [self updateStatus];
}

#pragma mark Toolbar

- (void)setupToolbar {
    // Create a new toolbar instance, and attach it to our document window
    NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier:SKBookmarksToolbarIdentifier] autorelease];
    SKToolbarItem *item;
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:3];
    
    // Set up toolbar properties: Allow customization, give a default display mode, and remember state in user defaults
    [toolbar setAllowsUserCustomization: YES];
    [toolbar setAutosavesConfiguration: YES];
    [toolbar setDisplayMode: NSToolbarDisplayModeDefault];
    
    // We are the delegate
    [toolbar setDelegate: self];
    
    // Add template toolbar items
    
    item = [[SKToolbarItem alloc] initWithItemIdentifier:SKBookmarksNewFolderToolbarItemIdentifier];
    [item setLabels:NSLocalizedString(@"New Folder", @"Toolbar item label")];
    [item setToolTip:NSLocalizedString(@"Add a New Folder", @"Tool tip message")];
    [item setImage:[NSImage imageNamed:SKImageNameNewFolder]];
    [item setTarget:self];
    [item setAction:@selector(insertBookmarkFolder:)];
    [dict setObject:item forKey:SKBookmarksNewFolderToolbarItemIdentifier];
    [item release];
    
    item = [[SKToolbarItem alloc] initWithItemIdentifier:SKBookmarksNewSeparatorToolbarItemIdentifier];
    [item setLabels:NSLocalizedString(@"New Separator", @"Toolbar item label")];
    [item setToolTip:NSLocalizedString(@"Add a New Separator", @"Tool tip message")];
    [item setImage:[NSImage imageNamed:SKImageNameNewSeparator]];
    [item setTarget:self];
    [item setAction:@selector(insertBookmarkSeparator:)];
    [dict setObject:item forKey:SKBookmarksNewSeparatorToolbarItemIdentifier];
    [item release];
    
    item = [[SKToolbarItem alloc] initWithItemIdentifier:SKBookmarksDeleteToolbarItemIdentifier];
    [item setLabels:NSLocalizedString(@"Delete", @"Toolbar item label")];
    [item setToolTip:NSLocalizedString(@"Delete Selected Items", @"Tool tip message")];
    [item setImage:[[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kToolbarDeleteIcon)]];
    [item setTarget:self];
    [item setAction:@selector(deleteBookmark:)];
    [dict setObject:item forKey:SKBookmarksDeleteToolbarItemIdentifier];
    [item release];
    
    toolbarItems = [dict mutableCopy];
    
    // Attach the toolbar to the window
    [[self window] setToolbar:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdent willBeInsertedIntoToolbar:(BOOL)willBeInserted {
    NSToolbarItem *item = [toolbarItems objectForKey:itemIdent];
    return item;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return [NSArray arrayWithObjects:
        SKBookmarksNewFolderToolbarItemIdentifier, 
        SKBookmarksNewSeparatorToolbarItemIdentifier, 
        SKBookmarksDeleteToolbarItemIdentifier, nil];
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [NSArray arrayWithObjects: 
        SKBookmarksNewFolderToolbarItemIdentifier, 
        SKBookmarksNewSeparatorToolbarItemIdentifier, 
		SKBookmarksDeleteToolbarItemIdentifier, 
        NSToolbarFlexibleSpaceItemIdentifier, 
		NSToolbarSpaceItemIdentifier, 
		NSToolbarSeparatorItemIdentifier, 
		NSToolbarCustomizeToolbarItemIdentifier, nil];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)toolbarItem {
    if ([[[self window] toolbar] customizationPaletteIsRunning])
        return NO;
    else if ([[toolbarItem itemIdentifier] isEqualToString:SKBookmarksDeleteToolbarItemIdentifier])
        return [outlineView canDelete];
    return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    if ([menuItem action] == @selector(toggleStatusBar:)) {
        if ([statusBar isVisible])
            [menuItem setTitle:NSLocalizedString(@"Hide Status Bar", @"Menu item title")];
        else
            [menuItem setTitle:NSLocalizedString(@"Show Status Bar", @"Menu item title")];
        return YES;
    } else if ([menuItem action] == @selector(addBookmark:)) {
        return [menuItem tag] == 0;
    } else if ([menuItem action] == @selector(copyURL:)) {
        return [outlineView selectedRow] >= 0;
    }
    return YES;
}

#pragma mark Quick Look Panel Support

- (BOOL)acceptsPreviewPanelControl:(QLPreviewPanel *)panel {
    return YES;
}

- (void)beginPreviewPanelControl:(QLPreviewPanel *)panel {
    [panel setDelegate:self];
    [panel setDataSource:self];
}

- (void)endPreviewPanelControl:(QLPreviewPanel *)panel {
}

- (NSArray *)previewItems {
    NSMutableArray *items = [NSMutableArray array];
    
    [[outlineView selectedRowIndexes] enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        SKBookmark *item = [outlineView itemAtRow:idx];
        if ([item bookmarkType] == SKBookmarkTypeBookmark)
            [items addObject:item];
        else if ([item bookmarkType] == SKBookmarkTypeSession)
            [items addObjectsFromArray:[item children]];
    }];
    return items;
}

- (NSInteger)numberOfPreviewItemsInPreviewPanel:(QLPreviewPanel *)panel {
    return [[self previewItems] count];
}

- (id <QLPreviewItem>)previewPanel:(QLPreviewPanel *)panel previewItemAtIndex:(NSInteger)anIndex {
    return [[self previewItems] objectAtIndex:anIndex];
}

- (NSRect)previewPanel:(QLPreviewPanel *)panel sourceFrameOnScreenForPreviewItem:(id <QLPreviewItem>)item {
    if ([[(SKBookmark *)item parent] bookmarkType] == SKBookmarkTypeSession)
        item = [(SKBookmark *)item parent];
    NSInteger row = [outlineView rowForItem:item];
    NSRect iconRect = NSZeroRect;
    if (item != nil && row != -1) {
        NSImageView *imageView = [[outlineView viewAtColumn:0 row:row makeIfNecessary:NO] imageView];
        if (imageView && NSIsEmptyRect([imageView visibleRect]) == NO)
            iconRect = [imageView convertRectToScreen:[imageView bounds]];
    }
    return iconRect;
}

- (NSImage *)previewPanel:(QLPreviewPanel *)panel transitionImageForPreviewItem:(id <QLPreviewItem>)item contentRect:(NSRect *)contentRect {
    if ([[(SKBookmark *)item parent] bookmarkType] == SKBookmarkTypeSession)
        item = [(SKBookmark *)item parent];
    return [(SKBookmark *)item icon];
}

- (BOOL)previewPanel:(QLPreviewPanel *)panel handleEvent:(NSEvent *)event {
    if ([event type] == NSKeyDown) {
        [outlineView keyDown:event];
        return YES;
    }
    return NO;
}

@end
