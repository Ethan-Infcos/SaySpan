#import <Cocoa/Cocoa.h>

NSString *KeyboardLayoutIdentifierForLanguage(NSString *language);
NSString *KeyboardLayoutNameForLanguage(NSString *language);
NSString *InputLanguageTypingMethod(NSString *language);

// Reads macOS layout tables without selecting another system input source.
@interface KeyboardLayoutEngine : NSObject
@property(nonatomic, copy) NSString *language;
@property(nonatomic, readonly) BOOL hasPendingAccent;
@property(nonatomic, copy, readonly) NSString *pendingText;
- (NSString *)takePendingText;
// nil means unhandled; an empty string means a consumed dead key.
- (NSString *)translateKey:(NSUInteger)code modifiers:(NSEventModifierFlags)flags;
- (void)reset;
@end
