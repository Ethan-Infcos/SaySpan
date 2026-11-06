#import "Core.h"
#import <NaturalLanguage/NaturalLanguage.h>

NSArray<NSString *> *InputLanguages(void) { return TranslationLanguages(); }
NSString *ReadFirstInputLanguage(void) {
    id saved = [NSUserDefaults.standardUserDefaults objectForKey:@"firstInputLanguage"];
    return [InputLanguages() containsObject:saved ?: @""] ? saved : @"en";
}
NSString *ReadSecondInputLanguage(void) {
    NSString *first = ReadFirstInputLanguage();
    id saved = [NSUserDefaults.standardUserDefaults objectForKey:@"secondInputLanguage"];
    return [InputLanguages() containsObject:saved ?: @""] && ![saved isEqual:first] ? saved : [first isEqual:@"zh"] ? @"en" : @"zh";
}
BOOL InputLanguageUsesPinyin(NSString *language) { return [language isEqual:@"zh"] || [language isEqual:@"zh-Hant"]; }
BOOL InputLanguageUsesCandidates(NSString *language) { return InputLanguageUsesPinyin(language) || [language isEqual:@"ja"]; }
BOOL InputLanguageUsesCapsLock(NSString *language) { return [ReadSecondInputLanguage() isEqual:language]; }
NSString *InputLanguageForModifiers(NSEventModifierFlags flags) {
    return flags & NSEventModifierFlagCapsLock ? ReadSecondInputLanguage() : ReadFirstInputLanguage();
}
NSArray<NSMenuItem *> *CreateInputLanguageMenuItems(NSString *language) {
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *code in @[ReadFirstInputLanguage(), ReadSecondInputLanguage()]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:TranslationLanguageName(code) action:NULL keyEquivalent:@""];
        item.enabled = NO;
        item.state = [code isEqual:language] ? NSControlStateValueOn : NSControlStateValueOff;
        item.toolTip = items.count ? L(@"Second language · Caps Lock light on") : L(@"First language · Caps Lock light off");
        [items addObject:item];
    }
    return items;
}
static NSString *PairLanguage(NSString *detected, NSString *first, NSString *second) {
    if ([detected isEqual:first] || [detected isEqual:second]) return detected;
    // Treat the other Chinese script as Chinese if only one script is in the pair.
    if ([detected isEqual:@"zh-Hant"] && [@[first, second] containsObject:@"zh"]) return @"zh";
    if ([detected isEqual:@"zh"] && [@[first, second] containsObject:@"zh-Hant"]) return @"zh-Hant";
    return nil;
}
NSString *PairTranslationTarget(NSString *text, NSString *fallbackSource) {
    text = text ?: @"";
    NSString *first = ReadFirstInputLanguage(), *second = ReadSecondInputLanguage();
    NSString *detected = DetectInputLanguage(text);
    NSString *source = PairLanguage(detected, first, second);
    if (!detected && [text rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location != NSNotFound) {
        // Short text may be ambiguous across all languages; compare only the configured pair.
        NLLanguageRecognizer *recognizer = [NLLanguageRecognizer new];
        recognizer.languageConstraints = @[[first isEqual:@"zh"] ? NLLanguageSimplifiedChinese : first,
                                          [second isEqual:@"zh"] ? NLLanguageSimplifiedChinese : second];
        [recognizer processString:text];
        NSDictionary *hypotheses = [recognizer languageHypothesesWithMaximum:1];
        if ([hypotheses.allValues.firstObject doubleValue] >= 0.65) {
            NSString *language = recognizer.dominantLanguage;
            if ([language isEqual:NLLanguageSimplifiedChinese]) language = @"zh";
            source = PairLanguage(language, first, second);
        }
    }
    if (!source) source = PairLanguage(fallbackSource, first, second);
    if ([source isEqual:first]) return second;
    if ([source isEqual:second]) return first;
    return first;
}
