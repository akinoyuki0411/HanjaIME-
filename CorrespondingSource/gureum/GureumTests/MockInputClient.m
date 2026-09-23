//
//  MockInputClient.m
//  OSXTestApp
//
//  Created by Jeong YunWon on 13/01/2019.
//  Copyright © 2019 youknowone.org. All rights reserved.
//

#import "MockInputClient.h"

@implementation MockInputClient

- (NSInteger)windowLevel { return self.simulatedWindowLevel; }

- (NSRect)firstRectForCharacterRange:(NSRange)range actualRange:(NSRangePointer)actualRange {
    if (actualRange) *actualRange = range;
    return self.simulatedCaret;
}

- (NSDictionary *)attributesForCharacterIndex:(NSUInteger)index lineHeightRectangle:(NSRect *)lineRect {
    self.lastAttributeIndex = index;
    if (self.useSimulatedAttributeCaret) {
        if (lineRect) *lineRect = index == self.expectedAttributeIndex ? self.simulatedAttributeCaret : NSZeroRect;
        return @{};
    }
    if (lineRect) *lineRect = NSMakeRect(100, 700, 10, 18);
    return @{};
}

- (NSRange)markedRange {
    return self.returnsInvalidMarkedRange ? NSMakeRange(NSNotFound, 0) : [super markedRange];
}

- (void)selectInputMode:(NSString *)modeIdentifier {
    NSLog(@"select input mode: %@", modeIdentifier);
}

- (NSInteger)length {
    return self.string.length;
}

- (NSString *)markedString {
    return [self.string substringWithRange:self.markedRange];
}

- (NSString *)selectedString {
    return [self.string substringWithRange:self.selectedRange];
}

- (void)insertText:(id)string replacementRange:(NSRange)replacementRange {
    // Model a remote proxy with a temporarily unavailable public markedRange;
    // the host text view still owns its actual internal marked-text state.
    BOOL unavailable = self.returnsInvalidMarkedRange;
    self.returnsInvalidMarkedRange = NO;
    @try { [super insertText:string replacementRange:replacementRange]; }
    @finally { self.returnsInvalidMarkedRange = unavailable; }
}

- (void)setMarkedText:(id)string selectionRange:(NSRange)selectionRange replacementRange:(NSRange)replacementRange {
    // Both protocols define selection relative to the new marked string.
    BOOL unavailable = self.returnsInvalidMarkedRange;
    self.returnsInvalidMarkedRange = NO;
    @try { [self setMarkedText:string selectedRange:selectionRange replacementRange:replacementRange]; }
    @finally { self.returnsInvalidMarkedRange = unavailable; }

//    NSRange s = self.selectedRange;
//    NSRange m = self.markedRange;
//    NSAssert(selected.location == s.location && selected.length == s.length, @"");
//    NSAssert(selected.location == m.location && selected.length == m.length, @"");
}

- (void)overrideKeyboardWithKeyboardNamed:(NSString *)keyboardUniqueName {
    self.keyboardOverrideCount += 1;
}

- (NSString *)bundleIdentifier {
    return [NSBundle mainBundle].bundleIdentifier;
}

@end
