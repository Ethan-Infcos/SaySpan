#import "Core.h"
#import "KeyboardLayoutEngine.h"

static NSUInteger checks, failures;
static void Check(BOOL condition, NSString *message) {
    checks++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); }
}
static void Pair(NSMutableDictionary *arguments, NSString *first, NSString *second) {
    arguments[@"firstInputLanguage"] = first;
    arguments[@"secondInputLanguage"] = second;
    [NSUserDefaults.standardUserDefaults setVolatileDomain:arguments forName:NSArgumentDomain];
}
static Composition *CompositionForLanguage(NSString *language) {
    Composition *c = [Composition new];
    c.baseInputLanguage = language;
    c.engine.learningEnabled = NO;
    c.service = ^(NSString *text, TranslationCompletion done) { done(@"Mock translation", nil); };
    return c;
}
static void Type(Composition *c, NSString *spelling) {
    for (NSUInteger i = 0; i < spelling.length; i++)
        [c handleKey:0 text:[spelling substringWithRange:NSMakeRange(i, 1)] modifiers:0];
}
static NSUInteger Candidate(PinyinEngine *engine, NSString *word) {
    for (NSUInteger page = 0; page < 20; page++) {
        NSUInteger index = [engine.candidates indexOfObject:word];
        if (index != NSNotFound) return index;
        if (![engine changePage:NO]) break;
    }
    return NSNotFound;
}
int RunTypingEngineTests(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *original = [defaults volatileDomainForName:NSArgumentDomain];
    NSMutableDictionary *arguments = original.mutableCopy;
    arguments[@"interfaceLanguage"] = @"en";
    arguments[@"translationProvider"] = @"ollama";
    arguments[@"learningEnabled"] = @NO;
    @try {
        Pair(arguments, @"en", @"zh-Hant");
        NSArray *languages = @[@"en", @"fr", @"de", @"es", @"pt", @"it", @"ru", @"ar", @"hi", @"th", @"vi", @"id"];
        KeyboardLayoutEngine *keyboard = [KeyboardLayoutEngine new];
        for (NSString *language in languages) {
            keyboard.language = language;
            Check(KeyboardLayoutNameForLanguage(language).length > 0, [@"Native keyboard is installed: " stringByAppendingString:language]);
            NSString *value = [keyboard translateKey:0 modifiers:0];
            NSString *pending = keyboard.pendingText;
            Check(value.length > 0 || pending.length > 0, [@"Native layout produces text: " stringByAppendingString:language]);
            [keyboard reset];
            Check([[keyboard translateKey:0 modifiers:NSEventModifierFlagCapsLock] isEqual:value] && [keyboard.pendingText isEqual:pending], @"Caps Lock language selection does not alter mapped characters");
            [keyboard reset];
            Check([keyboard translateKey:0 modifiers:NSEventModifierFlagCommand] == nil, @"Command shortcuts are not translated into layout characters");
            Check([keyboard translateKey:0 modifiers:NSEventModifierFlagControl] == nil, @"Control shortcuts stay with the host");
            Check([keyboard translateKey:36 modifiers:0] == nil && [keyboard translateKey:123 modifiers:0] == nil, @"Return and arrow keys remain editing commands");
        }
        keyboard.language = @"fr";
        Check([[keyboard translateKey:0 modifiers:0] isEqual:@"q"], @"French maps the physical A key to AZERTY Q");
        Check([[keyboard translateKey:18 modifiers:0] isEqual:@"&"] && [[keyboard translateKey:18 modifiers:NSEventModifierFlagShift | NSEventModifierFlagCapsLock] isEqual:@"1"], @"French Shift-number mapping survives the language-switch Caps flag");
        keyboard.language = @"de";
        Check([[keyboard translateKey:6 modifiers:0] isEqual:@"y"], @"German uses QWERTZ");
        keyboard.language = @"ru";
        NSMutableString *russian = [NSMutableString string];
        for (NSNumber *key in @[@5, @4, @11, @2, @17, @45]) [russian appendString:[keyboard translateKey:key.unsignedIntegerValue modifiers:0]];
        Check([russian isEqual:@"привет"], @"Russian produces a complete Cyrillic word");
        for (NSArray *fixture in @[@[@"ar", @0x0600, @0x06ff], @[@"hi", @0x0900, @0x097f], @[@"th", @0x0e00, @0x0e7f]]) {
            keyboard.language = fixture[0];
            NSString *value = [keyboard translateKey:0 modifiers:0];
            Check(value.length && [value characterAtIndex:0] >= [fixture[1] unsignedIntegerValue] && [value characterAtIndex:0] <= [fixture[2] unsignedIntegerValue], @"Arabic, Hindi, and Thai use their actual scripts");
        }
        keyboard.language = @"vi";
        Check([[keyboard translateKey:18 modifiers:0] isEqual:@""] && [keyboard.pendingText isEqual:@"ă"], @"Vietnamese exposes its native accented-letter key as a pending character");
        keyboard.language = @"en";
        Check([[keyboard translateKey:14 modifiers:NSEventModifierFlagOption] isEqual:@""] && keyboard.hasPendingAccent, @"An Option accent starts a dead-key sequence");
        Check([[keyboard translateKey:14 modifiers:0] isEqual:@"é"] && !keyboard.hasPendingAccent, @"The following letter completes the accented character");
        Check([keyboard translateKey:51 modifiers:0] == nil, @"Backspace after a completed accent deletes host text, not an invisible layout state");
        [keyboard translateKey:14 modifiers:NSEventModifierFlagOption];
        Check([[keyboard translateKey:51 modifiers:0] isEqual:@""] && !keyboard.hasPendingAccent, @"Backspace cancels a pending accent without deleting host text");
        [keyboard translateKey:14 modifiers:NSEventModifierFlagOption];
        keyboard.language = @"id";
        Check([[keyboard translateKey:14 modifiers:0] isEqual:@"e"], @"An unfinished accent cannot leak across languages");
        [keyboard translateKey:14 modifiers:NSEventModifierFlagOption];
        [keyboard reset];
        Check([[keyboard translateKey:14 modifiers:0] isEqual:@"e"], @"Focus reset clears the accent state");
        Check(!KeyboardLayoutIdentifierForLanguage(@"ja") && !KeyboardLayoutIdentifierForLanguage(@"ko") &&
              InputLanguageUsesCandidates(@"ja") && [InputLanguageTypingMethod(@"ko") containsString:@"planned"], @"Japanese uses conversion while Korean remains explicitly marked as planned");

        Pair(arguments, @"ru", @"en");
        Composition *direct = CompositionForLanguage(@"ru");
        __block NSString *inserted = @"";
        direct.committed = ^(NSString *text) { inserted = [inserted stringByAppendingString:text]; };
        for (NSNumber *key in @[@5, @4, @11, @2, @17, @45])
            [direct handlePhysicalKey:key.unsignedIntegerValue text:@"ignored host characters" modifiers:0];
        Check([inserted isEqual:@"привет"] && !direct.hasEditingSession, @"The production physical-key path directly inserts native script without a draft");
        [direct handlePhysicalKey:0 text:@"A" modifiers:NSEventModifierFlagCapsLock];
        Check([inserted isEqual:@"приветa"] && [direct.inputLanguage isEqual:@"en"], @"A missing flagsChanged event switches languages before translating the next key");
        Pair(arguments, @"id", @"zh");
        Composition *accent = CompositionForLanguage(@"id");
        __block NSString *accentOutput = @"";
        accent.committed = ^(NSString *text) { accentOutput = [accentOutput stringByAppendingString:text]; };
        [accent handlePhysicalKey:14 text:@"´" modifiers:NSEventModifierFlagOption];
        [accent handlePhysicalKey:14 text:@"e" modifiers:0];
        Check([accentOutput isEqual:@"é"] && !accent.hasEditingSession, @"Option dead keys are handled by the direct layout rather than discarded as shortcuts");
        [accent handlePhysicalKey:14 text:@"´" modifiers:NSEventModifierFlagOption];
        [accent cancel];
        [accent handlePhysicalKey:14 text:@"e" modifiers:0];
        Check([accentOutput isEqual:@"é´e"], @"Ending a client session finalizes pending text and does not leak its state");

        Pair(arguments, @"vi", @"en");
        Composition *vietnamese = CompositionForLanguage(@"vi");
        __block NSString *vietnameseOutput = @"";
        vietnamese.committed = ^(NSString *text) { vietnameseOutput = [vietnameseOutput stringByAppendingString:text]; };
        [vietnamese handlePhysicalKey:0 text:@"a" modifiers:0];
        Check(!vietnameseOutput.length && [vietnamese.pendingKeyboardText isEqual:@"a"] && [vietnamese.markedText isEqual:@"a"] && !vietnamese.hasEditingSession, @"Vietnamese pending vowels are visible as marked text without a translation draft");
        Check(![vietnamese handlePhysicalKey:36 text:@"\r" modifiers:0] && [vietnameseOutput isEqual:@"a"] && !vietnamese.pendingKeyboardText.length, @"Return preserves the last pending vowel before passing through");
        [vietnamese handlePhysicalKey:18 text:@"1" modifiers:0];
        [vietnamese handleModifiers:NSEventModifierFlagCapsLock];
        Check([vietnameseOutput isEqual:@"aă"] && !vietnamese.pendingKeyboardText.length, @"Switching languages finalizes a pending Vietnamese character");
        [vietnamese handleModifiers:0];
        [vietnamese handlePhysicalKey:0 text:@"a" modifiers:0];
        [vietnamese handlePhysicalKey:53 text:@"\e" modifiers:0];
        Check([vietnameseOutput isEqual:@"aă"] && !vietnamese.pendingKeyboardText.length, @"Escape cancels pending marked text without committing it");

        Pair(arguments, @"zh", @"ru");
        Composition *mixed = CompositionForLanguage(@"zh");
        Type(mixed, @"nihao");
        NSUInteger index = Candidate(mixed.engine, @"你好");
        Check(index != NSNotFound, @"The original Simplified Chinese dictionary is preserved");
        if (index != NSNotFound) [mixed chooseCandidate:index];
        __block NSString *mixedOutput = @"";
        mixed.committed = ^(NSString *text) { mixedOutput = [mixedOutput stringByAppendingString:text]; };
        [mixed handleModifiers:NSEventModifierFlagCapsLock];
        Check([mixedOutput isEqual:@"你好"] && !mixed.hasEditingSession, @"Caps inserts the Chinese sentence before selecting the Russian keyboard");
        for (NSNumber *key in @[@5, @4, @11, @2, @17, @45])
            [mixed handlePhysicalKey:key.unsignedIntegerValue text:@"unused" modifiers:NSEventModifierFlagCapsLock];
        Check([mixedOutput isEqual:@"你好привет"] && [mixed.inputLanguage isEqual:@"ru"], @"Native typing follows the inserted sentence directly in the host");
        Check(![mixed handlePhysicalKey:6 text:@"z" modifiers:NSEventModifierFlagCommand | NSEventModifierFlagCapsLock], @"Undo after switching belongs to the host and cannot restore an old draft");
        Check(![mixed handlePhysicalKey:6 text:@"z" modifiers:NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagCapsLock], @"Host redo is preserved after switching");
        [mixed cancel];

        Pair(arguments, @"zh-Hant", @"en");
        Composition *traditional = CompositionForLanguage(@"zh-Hant");
        Check([traditional.engine.language isEqual:@"zh-Hant"] && InputLanguageUsesPinyin(@"zh-Hant"), @"Traditional Chinese uses its own pinyin schema");
        Type(traditional, @"ceshi");
        index = Candidate(traditional.engine, @"測試");
        Check(index != NSNotFound, @"Traditional candidates are converted before presentation");
        if (index != NSNotFound) [traditional chooseCandidate:index];
        Check([traditional.chinese isEqual:@"測試"], @"Choosing a Traditional candidate preserves the same characters in the sentence");
        [traditional handleKey:6 text:@"z" modifiers:NSEventModifierFlagCommand];
        Check([traditional.engine.language isEqual:@"zh-Hant"] && traditional.engine.preedit.length, @"Undo restores the correct script-specific candidate engine");
        [traditional handleKey:6 text:@"z" modifiers:NSEventModifierFlagCommand | NSEventModifierFlagShift];
        Check([traditional.chinese isEqual:@"測試"], @"Redo restores the exact Traditional candidate");
        __block NSString *traditionalCommit;
        traditional.committed = ^(NSString *text) { traditionalCommit = text; };
        [traditional commitChinese];
        Check([traditionalCommit isEqual:@"測試"], @"Traditional text is committed unchanged");
        traditional.engine.learningEnabled = YES;
        Type(traditional, @"ceshi");
        Check(Candidate(traditional.engine, @"測試") != NSNotFound, @"Enabling learning retains Traditional candidate conversion");
        [traditional cancel];
        traditional.engine.learningEnabled = NO;
        Pair(arguments, @"zh", @"zh-Hant");
        Composition *scripts = CompositionForLanguage(@"zh");
        Type(scripts, @"ni");
        NSString *selected = scripts.engine.candidates[scripts.engine.highlighted];
        __block NSString *scriptOutput;
        scripts.committed = ^(NSString *text) { scriptOutput = text; };
        [scripts handleModifiers:NSEventModifierFlagCapsLock];
        Check([scriptOutput isEqual:selected] && [scripts.engine.language isEqual:@"zh-Hant"], @"Switching scripts confirms the selected Simplified candidate before opening the Traditional engine");
        [scripts cancel];
        Check([scripts.engine.language isEqual:@"zh-Hant"] && [scripts.inputLanguage isEqual:@"zh-Hant"], @"Closing a draft never reverses the physical Caps language");
        [scripts handlePhysicalKey:45 text:@"n" modifiers:NSEventModifierFlagCapsLock];
        [scripts handlePhysicalKey:0 text:@"a" modifiers:0];
        Check([scripts.engine.language isEqual:@"zh"] && [scripts.engine.rawInput isEqual:@"a"], @"A missed Caps event commits the previous script before starting the new one");
        [scripts handlePhysicalKey:6 text:@"z" modifiers:NSEventModifierFlagCommand];
        Check(!scripts.engine.preedit.length && !scripts.chinese.length, @"The first key after a missed language transition has its own undo entry");
        [scripts cancel];
    } @finally { [defaults setVolatileDomain:original forName:NSArgumentDomain]; }
    printf("Typing engines: %lu checks, %lu failures\n", checks, failures);
    return failures ? 1 : 0;
}
