//
//  MockInputClient.h
//  OSXTestApp
//
//  Created by Jeong YunWon on 13/01/2019.
//  Copyright © 2019 youknowone.org. All rights reserved.
//

@import Cocoa;
@import InputMethodKit;

NS_ASSUME_NONNULL_BEGIN

@interface MockInputClient : NSTextView<IMKTextInput, IMKUnicodeTextInput>

@property NSInteger simulatedWindowLevel;
@property NSRect simulatedCaret;
@property BOOL useSimulatedAttributeCaret;
@property NSRect simulatedAttributeCaret;
@property NSUInteger expectedAttributeIndex;
@property NSUInteger lastAttributeIndex;
@property BOOL returnsInvalidMarkedRange;
@property NSInteger keyboardOverrideCount;

- (NSString *)markedString;
- (NSString *)selectedString;

@end

NS_ASSUME_NONNULL_END
