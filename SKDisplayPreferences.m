//
//  SKDisplayPreferences.m
//  Skim
//
//  Created by Christiaan Hofman on 3/14/10.
/*
 This software is Copyright (c) 2010-2019
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

#import "SKDisplayPreferences.h"
#import "SKPreferenceController.h"
#import "SKStringConstants.h"
#import "NSGraphics_SKExtensions.h"
#import "NSImage_SKExtensions.h"
#import "NSUserDefaults_SKExtensions.h"
#import "NSUserDefaultsController_SKExtensions.h"
#import "NSColor_SKExtensions.h"
#import "NSValueTransformer_SKExtensions.h"
#import "SKColorSwatch.h"

static CGFloat SKDefaultFontSizes[] = {8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 32.0, 48.0, 64.0};

static char SKDisplayPreferencesDefaultsObservationContext;
static char SKDisplayPreferencesColorSwatchObservationContext;

@interface SKDisplayPreferences (Private)
- (void)updateBackgroundColors;
@end
    
@implementation SKDisplayPreferences

@synthesize tableFontLabelField, tableFontComboBox, greekingLabelField, greekingTextField, antiAliasCheckButton, colorSwatch, addRemoveColorButton, thumbnailSizeLabels, thumbnailSizeControls, colorLabels, colorControls;

- (void)dealloc {
    if (RUNNING_AFTER(10_13)) {
        @try {
            [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self forKeys:[NSArray arrayWithObjects:SKBackgroundColorKey, SKFullScreenBackgroundColorKey, SKDarkBackgroundColorKey, SKDarkFullScreenBackgroundColorKey, nil]];
            [colorSwatch unbind:@"colors"];
        }
        @catch(id e) {}
    }
    SKDESTROY(tableFontLabelField);
    SKDESTROY(tableFontComboBox);
    SKDESTROY(greekingLabelField);
    SKDESTROY(greekingTextField);
    SKDESTROY(antiAliasCheckButton);
    SKDESTROY(colorSwatch);
    SKDESTROY(addRemoveColorButton);
    SKDESTROY(thumbnailSizeLabels);
    SKDESTROY(thumbnailSizeControls);
    SKDESTROY(colorLabels);
    SKDESTROY(colorControls);
    [super dealloc];
}

- (NSString *)nibName {
    return @"DisplayPreferences";
}

- (void)loadView {
    [super loadView];
    
    [[self view] setFrameSize:[[self view] fittingSize]];
    
    NSDictionary *options = [NSDictionary dictionaryWithObject:SKUnarchiveFromDataArrayTransformerName forKey:NSValueTransformerNameBindingOption];
    [colorSwatch bind:@"colors" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:[@"values." stringByAppendingString:SKSwatchColorsKey] options:options];
    [colorSwatch sizeToFit];
    [colorSwatch setSelects:YES];
    if (!RUNNING_BEFORE(10_10))
        [colorSwatch setFrame:NSOffsetRect([colorSwatch frame], 0.0, 1.0)];
    [colorSwatch addObserver:self forKeyPath:@"selectedColorIndex" options:0 context:&SKDisplayPreferencesColorSwatchObservationContext];
    
    if (RUNNING_AFTER(10_13)) {
        NSColorWell *colorWell;
        colorWell = [colorControls objectAtIndex:0];
        [colorWell unbind:NSValueBinding];
        [colorWell setAction:@selector(changeBackgroundColor:)];
        [colorWell setTarget:self];
        colorWell = [colorControls objectAtIndex:2];
        [colorWell unbind:NSValueBinding];
        [colorWell setAction:@selector(changeFullScreenBackgroundColor:)];
        [colorWell setTarget:self];
        
        [self updateBackgroundColors];
        
        [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeys:[NSArray arrayWithObjects:SKBackgroundColorKey, SKFullScreenBackgroundColorKey, SKDarkBackgroundColorKey, SKDarkFullScreenBackgroundColorKey, nil] context:&SKDisplayPreferencesDefaultsObservationContext];
        [NSApp addObserver:self forKeyPath:@"effectiveAppearance" options:0 context:&SKDisplayPreferencesDefaultsObservationContext];
    }
}

#pragma mark Accessors

- (NSString *)title { return NSLocalizedString(@"Display", @"Preference pane label"); }

- (NSUInteger)countOfSizes {
    return sizeof(SKDefaultFontSizes) / sizeof(CGFloat);
}

- (NSNumber *)objectInSizesAtIndex:(NSUInteger)anIndex {
    return [NSNumber numberWithDouble:SKDefaultFontSizes[anIndex]];
}

#pragma mark Actions

- (IBAction)changeDiscreteThumbnailSizes:(id)sender {
    NSSlider *slider1 = [thumbnailSizeControls objectAtIndex:0];
    NSSlider *slider2 = [thumbnailSizeControls objectAtIndex:1];
    if ([(NSButton *)sender state] == NSOnState) {
        [slider1 setNumberOfTickMarks:8];
        [slider2 setNumberOfTickMarks:8];
        [slider1 setAllowsTickMarkValuesOnly:YES];
        [slider2 setAllowsTickMarkValuesOnly:YES];
    } else {
        [[slider1 superview] setNeedsDisplayInRect:[slider1 frame]];
        [[slider2 superview] setNeedsDisplayInRect:[slider2 frame]];
        [slider1 setNumberOfTickMarks:0];
        [slider2 setNumberOfTickMarks:0];
        [slider1 setAllowsTickMarkValuesOnly:NO];
        [slider2 setAllowsTickMarkValuesOnly:NO];
    }
    [slider1 sizeToFit];
    [slider2 sizeToFit];
}

- (IBAction)changeBackgroundColor:(id)sender {
    NSString *key = SKHasDarkAppearance(NSApp) ? SKDarkBackgroundColorKey : SKBackgroundColorKey;
    changingColors = YES;
    [[NSUserDefaults standardUserDefaults] setColor:[sender color] forKey:key];
    changingColors = YES;
}

- (IBAction)changeFullScreenBackgroundColor:(id)sender{
    NSString *key = SKHasDarkAppearance(NSApp) ? SKDarkFullScreenBackgroundColorKey : SKFullScreenBackgroundColorKey;
    changingColors = YES;
    [[NSUserDefaults standardUserDefaults] setColor:[sender color] forKey:key];
    changingColors = NO;
}

- (IBAction)addRemoveColor:(id)sender {
    NSInteger i = [colorSwatch selectedColorIndex];
    if ([sender selectedTag] == 0) {
        if (i == -1)
            i = [[colorSwatch colors] count];
        NSColor *color = [NSColor colorWithCalibratedRed:1.0 green:1.0 blue:0.5 alpha:1.0];
        [colorSwatch insertColor:color atIndex:i];
        [colorSwatch selectColorAtIndex:i];
    } else {
        if (i != -1)
            [colorSwatch removeColorAtIndex:i];
    }
}

#pragma mark KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context == &SKDisplayPreferencesDefaultsObservationContext) {
        if (changingColors == NO)
            [self updateBackgroundColors];
    } else if (context == &SKDisplayPreferencesColorSwatchObservationContext) {
        [addRemoveColorButton setEnabled:[colorSwatch selectedColorIndex] != -1 forSegment:1];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark Private

- (void)updateBackgroundColors {
    NSUserDefaults *sud = [NSUserDefaults standardUserDefaults];
    NSColor *backgroundColor = nil;
    NSColor *fullScreenBackgroundColor = nil;
    if (SKHasDarkAppearance(NSApp)) {
        backgroundColor = [sud colorForKey:SKDarkBackgroundColorKey];
        fullScreenBackgroundColor = [sud colorForKey:SKDarkFullScreenBackgroundColorKey];
    }
    if (backgroundColor == nil)
        backgroundColor = [sud colorForKey:SKBackgroundColorKey];
    if (fullScreenBackgroundColor == nil)
        fullScreenBackgroundColor = [sud colorForKey:SKFullScreenBackgroundColorKey];
    [[colorControls objectAtIndex:0] setColor:backgroundColor];
    [[colorControls objectAtIndex:2] setColor:fullScreenBackgroundColor];
}

@end
