#import "KeyboardLayoutEngine.h"
#import "Core.h"
#import <Carbon/Carbon.h>

NSString *KeyboardLayoutIdentifierForLanguage(NSString *language) {
    return @{@"en":@"com.apple.keylayout.ABC", @"fr":@"com.apple.keylayout.French",
        @"de":@"com.apple.keylayout.German", @"es":@"com.apple.keylayout.Spanish-ISO",
        @"pt":@"com.apple.keylayout.Portuguese", @"it":@"com.apple.keylayout.Italian-Pro",
        @"ru":@"com.apple.keylayout.Russian", @"ar":@"com.apple.keylayout.Arabic",
        @"hi":@"com.apple.keylayout.Devanagari", @"th":@"com.apple.keylayout.Thai",
        @"vi":@"com.apple.keylayout.Vietnamese", @"id":@"com.apple.keylayout.ABC"}[language ?: @""];
}
static NSDictionary *Layout(NSString *language) {
    NSString *identifier = KeyboardLayoutIdentifierForLanguage(language);
    if (!identifier) return nil;
    static NSMutableDictionary *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    if (cache[identifier]) return cache[identifier];
    NSDictionary *filter = @{(__bridge NSString *)kTISPropertyInputSourceID:identifier,
        (__bridge NSString *)kTISPropertyInputSourceType:(__bridge NSString *)kTISTypeKeyboardLayout};
    NSArray *sources = CFBridgingRelease(TISCreateInputSourceList((__bridge CFDictionaryRef)filter, true));
    for (id object in sources) {
        TISInputSourceRef source = (__bridge TISInputSourceRef)object;
        NSData *data = (__bridge NSData *)TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData);
        NSString *name = (__bridge NSString *)TISGetInputSourceProperty(source, kTISPropertyLocalizedName);
        if (data.length) {
            NSDictionary *layout = @{@"data":data.copy, @"name":name ?: identifier};
            cache[identifier] = layout;
            return layout;
        }
    }
    return nil;
}
NSString *KeyboardLayoutNameForLanguage(NSString *language) { return Layout(language)[@"name"]; }
NSString *InputLanguageTypingMethod(NSString *language) {
    if ([language isEqual:@"zh"]) return L(@"Pinyin · Simplified Chinese candidates");
    if ([language isEqual:@"zh-Hant"]) return L(@"Pinyin · Traditional Chinese candidates");
    if ([language isEqual:@"ja"]) return L(@"Romaji · Hiragana, katakana and kanji candidates");
    if ([language isEqual:@"ko"])
        return L(@"Typing engine planned · ABC typing only for now");
    NSString *name = KeyboardLayoutNameForLanguage(language);
    return name ? [NSString stringWithFormat:L(@"Keyboard: %@ · Direct typing"), name]
                : L(@"Keyboard unavailable on this Mac · ABC fallback");
}
@implementation KeyboardLayoutEngine {
    UInt32 _deadKeyState;
}
- (void)setLanguage:(NSString *)language {
    if ([_language isEqual:language]) return;
    _language = language.copy;
    [self reset];
}
- (BOOL)hasPendingAccent { return self.pendingText.length != 0; }
- (void)reset { _deadKeyState = 0; }
- (NSString *)pendingText {
    if (!_deadKeyState) return @"";
    NSData *data = Layout(_language)[@"data"];
    if (!data.length) return @"";
    UInt32 state = _deadKeyState;
    UniChar output[255];
    UniCharCount length = 0;
    OSStatus status = UCKeyTranslate((const UCKeyboardLayout *)data.bytes, 49, kUCKeyActionDown,
        0, LMGetKbdType(), kUCKeyTranslateNoDeadKeysMask, &state, 255, &length, output);
    if (status != noErr) return @"";
    NSString *text = [NSString stringWithCharacters:output length:length];
    // Space flushes the layout state; do not include the synthetic separator.
    if ([text hasSuffix:@" "]) text = [text substringToIndex:text.length - 1];
    return text.precomposedStringWithCanonicalMapping;
}
- (NSString *)takePendingText {
    NSString *text = self.pendingText;
    [self reset];
    return text;
}
- (NSString *)translateKey:(NSUInteger)code modifiers:(NSEventModifierFlags)flags {
    if (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)) return nil;
    if (self.hasPendingAccent && (code == 51 || code == 53)) { [self reset]; return @""; }
    BOOL textKey = (code < 51 && code != 36 && code != 48) ||
        [@[@65, @67, @69, @75, @78, @81, @82, @83, @84, @85, @86, @87, @88, @89, @91, @92, @93, @94, @95] containsObject:@(code)];
    if (!textKey) return nil;
    NSData *data = Layout(_language)[@"data"];
    if (!data.length) { [self reset]; return nil; }
    // Caps Lock selects the language; only Shift and Option affect its characters.
    UInt32 modifiers = ((flags & NSEventModifierFlagShift ? shiftKey : 0) |
                        (flags & NSEventModifierFlagOption ? optionKey : 0)) >> 8;
    UniChar output[255];
    UniCharCount length = 0;
    OSStatus status = UCKeyTranslate((const UCKeyboardLayout *)data.bytes, (UInt16)code, kUCKeyActionDown,
        modifiers, LMGetKbdType(), 0, &_deadKeyState, 255, &length, output);
    if (status != noErr) { [self reset]; return nil; }
    return [[NSString stringWithCharacters:output length:length] precomposedStringWithCanonicalMapping];
}
@end
