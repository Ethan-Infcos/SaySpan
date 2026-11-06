#import "Core.h"
#import "SelectionTranslation.h"

static NSUInteger checks, failures;
static void Check(BOOL condition, NSString *message) {
    checks++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); }
}
static void SetPair(NSMutableDictionary *arguments, NSString *first, NSString *second) {
    arguments[@"firstInputLanguage"] = first;
    arguments[@"secondInputLanguage"] = second;
    [NSUserDefaults.standardUserDefaults setVolatileDomain:arguments forName:NSArgumentDomain];
}
static Composition *DraftComposition(NSString *language) {
    Composition *composition = [Composition new];
    composition.baseInputLanguage = language;
    composition.engine.learningEnabled = NO;
    composition.service = ^(NSString *text, TranslationCompletion completion) { completion(@"Translated fixture", nil); };
    return composition;
}
static void Type(Composition *c, NSString *text, NSEventModifierFlags flags) {
    for (NSUInteger i = 0; i < text.length; i++)
        [c handlePhysicalKey:0 text:[text substringWithRange:NSMakeRange(i, 1)] modifiers:flags];
}
static void Pump(NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (end.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
static void TestKeyboardSwitching(NSMutableDictionary *arguments) {
    SetPair(arguments, @"en", @"zh");
    NSEventModifierFlags caps = NSEventModifierFlagCapsLock;
    Composition *c = DraftComposition(@"en");
    NSMutableArray *commits = [NSMutableArray array], *languagesAtCommit = [NSMutableArray array], *responses = [NSMutableArray array];
    __weak Composition *weak = c;
    c.committed = ^(NSString *text) { [commits addObject:text]; [languagesAtCommit addObject:weak.inputLanguage]; };
    c.service = ^(NSString *text, TranslationCompletion done) { [responses addObject:[done copy]]; };
    [c synchronizeModifiers:0];
    Type(c, @"hello", 0);
    Check([[commits componentsJoinedByString:@""] isEqual:@"hello"] && !c.hasEditingSession, @"Caps off starts in direct English");
    [commits removeAllObjects]; [languagesAtCommit removeAllObjects];
    [c handleModifiers:caps];
    Type(c, @"shi", caps);
    [c handlePhysicalKey:124 text:@"" modifiers:caps];
    NSString *highlighted = c.engine.candidates[c.engine.highlighted];
    Check(c.engine.highlighted == 1, @"Switch fixture highlights a candidate other than the first");
    [c handleModifiers:0];
    Check(commits.count == 1 && [commits.lastObject isEqual:highlighted] && [languagesAtCommit.lastObject isEqual:@"zh"], @"Caps confirms the highlighted candidate and inserts source before changing language");
    Check(c.inputEnglish && c.directEnglish && !c.hasEditingSession, @"The draft closes and English remains selected");
    [c handleModifiers:0];
    Check(commits.count == 1 && c.inputEnglish, @"Repeated Caps state cannot insert twice or reverse the switch");
    Check(![c handlePhysicalKey:36 text:@"\r" modifiers:0] && ![c handlePhysicalKey:48 text:@"\t" modifiers:0], @"Enter and Tab after the switch belong to the host");
    Type(c, @"ok", 0);
    Check([commits.lastObject isEqual:@"k"] && !c.hasEditingSession, @"The next word stays direct instead of reopening the prior language's draft");
    [c handleModifiers:caps];
    Type(c, @"nihao", caps);
    [c handlePhysicalKey:49 text:@" " modifiers:caps];
    c.pasteText = ^{ return @" API"; };
    [c handlePhysicalKey:9 text:@"v" modifiers:caps | NSEventModifierFlagCommand];
    Pump(0.4);
    TranslationCompletion pending = responses.lastObject;
    Check(pending != nil, @"A translation is in flight before switching");
    NSUInteger before = commits.count;
    [c handleModifiers:0];
    Check(commits.count == before + 1 && [commits.lastObject isEqual:@"你好 API"], @"A mixed sentence inserts its source without waiting for translation");
    if (pending) pending(@"LATE TRANSLATION", nil);
    Pump(0.02);
    Check(!c.hasEditingSession && !c.english.length && commits.count == before + 1, @"Late translation cannot reopen or overwrite the committed sentence");
    Check(![c handlePhysicalKey:6 text:@"z" modifiers:NSEventModifierFlagCommand], @"Undo cannot resurrect the closed draft");

    [c handleModifiers:caps]; Type(c, @"nihao", caps);
    [c handlePhysicalKey:49 text:@" " modifiers:caps];
    [c handlePhysicalKey:123 text:@"" modifiers:caps];
    Type(c, @"shi", caps); [c handlePhysicalKey:124 text:@"" modifiers:caps];
    highlighted = c.engine.candidates[c.engine.highlighted];
    [c handleModifiers:0];
    Check([commits.lastObject isEqual:[NSString stringWithFormat:@"你%@好", highlighted]], @"The selected candidate is inserted at the sentence's middle caret before committing");

    [c handleModifiers:caps]; Type(c, @"womenmingtian", caps); [c expandCandidates];
    NSUInteger prefix = [c.engine.candidates indexOfObject:@"我们"];
    Check(prefix != NSNotFound, @"Partial-phrase fixture exposes a selectable prefix");
    if (prefix != NSNotFound) [c chooseCandidate:prefix];
    Check(c.engine.preedit.length > 0, @"A partial candidate leaves remaining spelling");
    [c handleModifiers:0];
    Check([commits.lastObject isEqual:@"我们明天"], @"Switching completes the remaining candidates without losing a selected prefix");

    [c handleModifiers:caps]; Type(c, @"i", caps);
    Check(!c.engine.candidates.count, @"Unconvertible spelling fixture has no candidates");
    [c handleModifiers:0];
    Check([commits.lastObject isEqual:@"i"], @"Unconvertible raw spelling is preserved instead of discarded");

    [c handleModifiers:caps]; Type(c, @"ni", caps);
    highlighted = c.engine.candidates[c.engine.highlighted]; before = commits.count;
    // Simulate an omitted flagsChanged event: this key must first finish the old draft.
    [c handlePhysicalKey:0 text:@"a" modifiers:0];
    Check(commits.count == before + 2 && [commits[before] isEqual:highlighted] && [commits.lastObject isEqual:@"a"] && c.inputEnglish, @"Key-down modifier recovery commits the old source before typing in the new language");
    [c synchronizeModifiers:caps]; Type(c, @"ni", caps);
    highlighted = c.engine.candidates[c.engine.highlighted];
    [c handleModifiers:NSEventModifierFlagShift];
    Check([commits.lastObject isEqual:highlighted] && c.inputEnglish, @"Caps switching has priority over simultaneous Shift handling");

    for (NSNumber *key in @[@36, @48]) {
        [c synchronizeModifiers:caps]; Type(c, @"nihao", caps);
        [c handlePhysicalKey:49 text:@" " modifiers:caps]; Pump(0.4);
        TranslationCompletion done = responses.lastObject;
        if (done) done(@"Hello", nil); Pump(0.02);
        [c handlePhysicalKey:key.unsignedIntegerValue text:key.intValue == 36 ? @"\r" : @"\t" modifiers:caps];
        Check(!c.hasEditingSession && [c.inputLanguage isEqual:@"zh"], @"Normal Enter/Tab insertion keeps the current physical Caps language");
        Type(c, @"n", caps);
        Check([c.engine.rawInput isEqual:@"n"], @"A new draft uses the same physical state after Enter/Tab");
        [c cancel];
    }
    [c synchronizeModifiers:caps]; Type(c, @"ni", caps);
    [c handlePhysicalKey:0 text:@"a" modifiers:caps | NSEventModifierFlagCommand];
    [c handlePhysicalKey:51 text:@"" modifiers:caps];
    Check(c.hasEditingSession && !c.hasComposition, @"Deleting the entire draft leaves an empty undo session");
    before = commits.count;
    [c handleModifiers:0];
    Check(!c.hasEditingSession && c.inputEnglish && commits.count == before, @"Caps closes an empty undo session without inserting empty text");
}

int RunLanguagePairTests(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *original = [defaults volatileDomainForName:NSArgumentDomain];
    NSMutableDictionary *arguments = original.mutableCopy;
    arguments[@"interfaceLanguage"] = @"en";
    arguments[@"translationProvider"] = @"ollama";
    @try {
        SetPair(arguments, @"fr", @"de");
        Check(InputLanguages().count == 16 && [InputLanguages() isEqual:TranslationLanguages()], @"The configured slots use all supported languages");
        Check([InputLanguageForModifiers(0) isEqual:@"fr"] && [InputLanguageForModifiers(NSEventModifierFlagCapsLock) isEqual:@"de"], @"Caps state maps directly to the configured pair order");
        NSArray<NSMenuItem *> *items = CreateInputLanguageMenuItems(@"de");
        Check(items.count == 2 && [items[0].title isEqual:@"French"] && [items[1].title isEqual:@"German"], @"Read-only menu status names use the actual configured pair");
        Check(items[0].state == NSControlStateValueOff && items[1].state == NSControlStateValueOn, @"Only the physical keyboard language has a checkmark");
        Check(!items[0].enabled && !items[1].enabled && !items[0].action && !items[1].action, @"Neither menu language can dispatch a switching action");
        Composition *direct = DraftComposition(@"fr");
        __block NSString *inserted = @"";
        __block NSUInteger requests = 0;
        direct.committed = ^(NSString *text) { inserted = [inserted stringByAppendingString:text]; };
        direct.service = ^(NSString *text, TranslationCompletion done) { requests++; };
        [direct synchronizeModifiers:NSEventModifierFlagCapsLock];
        Check([direct.inputLanguage isEqual:@"de"] && !direct.hasEditingSession, @"Activating with Caps on selects the second language immediately");
        [direct handleKey:0 text:@"H" modifiers:NSEventModifierFlagCapsLock];
        [direct handleKey:0 text:@"I" modifiers:NSEventModifierFlagCapsLock | NSEventModifierFlagShift];
        Check([inserted isEqual:@"hI"] && !direct.hasEditingSession && requests == 0, @"Direct input preserves Shift capitalization without translation");
        [direct handleModifiers:0];
        Check([direct.inputLanguage isEqual:@"fr"], @"Caps off selects the first language");
        Check(![direct handleModifiers:0] && [direct.inputLanguage isEqual:@"fr"], @"Repeated events do not toggle twice");
        SetPair(arguments, @"de", @"fr");
        [direct synchronizeModifiers:NSEventModifierFlagCapsLock];
        Check([direct.inputLanguage isEqual:@"fr"], @"Reordering settings while Caps is on keeps the second slot authoritative");
        [direct synchronizeModifiers:0];
        Check([direct.inputLanguage isEqual:@"de"], @"Reactivation with Caps off selects the new first slot");
        TestKeyboardSwitching(arguments);
        NSArray *fixtures = @[
            @[@"en", @"zh", @"Please confirm the meeting time tomorrow.", @"请确认明天的会议时间。"],
            @[@"en", @"fr", @"We will discuss the proposal tomorrow.", @"Nous allons discuter de la proposition demain."],
            @[@"ja", @"ko", @"明日の会議の時間を確認してください。", @"내일 회의 시간을 확인해 주세요."],
            @[@"es", @"de", @"La reunión es mañana por la mañana.", @"Bitte bestätigen Sie die Uhrzeit für unser Treffen morgen."]
        ];
        for (NSArray *fixture in fixtures) {
            SetPair(arguments, fixture[0], fixture[1]);
            for (NSUInteger direction = 0; direction < 2; direction++) {
                NSString *text = fixture[direction + 2], *target = fixture[1 - direction];
                Check([PairTranslationTarget(text, fixture[direction]) isEqual:target], @"Composition detects a pair member and translates into the other");
                Check([TranslationTargetForText(text, @"auto") isEqual:target], @"Selection uses the same bidirectional rule");
            }
        }
        SetPair(arguments, @"en", @"zh");
        Check([PairTranslationTarget(@"hello", nil) isEqual:@"zh"] && [PairTranslationTarget(@"你好", nil) isEqual:@"en"], @"Short words work in both directions");
        Check([PairTranslationTarget(@"請確認明天的會議時間。", nil) isEqual:@"en"], @"The other Chinese script is recognized when only one script belongs to the pair");
        Check([PairTranslationTarget(@"123 👋", nil) isEqual:@"en"] && [PairTranslationTarget(nil, nil) isEqual:@"en"], @"Uncertain selections safely use the first language");
        Check([PairTranslationTarget(@"123", @"en") isEqual:@"zh"], @"An ambiguous draft uses its current input language as the source fallback");
        arguments[@"firstInputLanguage"] = @42;
        arguments[@"secondInputLanguage"] = @"en";
        [defaults setVolatileDomain:arguments forName:NSArgumentDomain];
        Check([ReadFirstInputLanguage() isEqual:@"en"] && [ReadSecondInputLanguage() isEqual:@"zh"], @"Invalid or duplicate stored languages produce a valid distinct pair");
    } @finally { [defaults setVolatileDomain:original forName:NSArgumentDomain]; }
    printf("Language pair: %lu checks, %lu failures\n", checks, failures);
    return failures ? 1 : 0;
}
