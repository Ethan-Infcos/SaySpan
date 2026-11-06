#import "Core.h"

static NSUInteger checks, failures;
static const NSEventModifierFlags JapaneseFlags = NSEventModifierFlagCapsLock;
static void Check(BOOL condition, NSString *message) {
    checks++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); }
}
static void Type(Composition *c, NSString *text) {
    for (NSUInteger i = 0; i < text.length; i++)
        [c handlePhysicalKey:0 text:[text substringWithRange:NSMakeRange(i, 1)] modifiers:JapaneseFlags];
}
static BOOL Choose(Composition *c, NSString *word) {
    [c expandCandidates];
    for (NSUInteger page = 0; page < 40; page++) {
        NSUInteger index = [c.engine.candidates indexOfObject:word];
        if (index != NSNotFound) { [c chooseCandidate:index]; return YES; }
        if (!c.engine.candidatePage.hasNextPage) break;
        [c changeCandidatePage:NO];
    }
    return NO;
}
static void Pump(NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (end.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
int RunJapaneseTests(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *original = [defaults volatileDomainForName:NSArgumentDomain];
    NSMutableDictionary *arguments = original.mutableCopy;
    arguments[@"firstInputLanguage"] = @"en";
    arguments[@"secondInputLanguage"] = @"ja";
    arguments[@"interfaceLanguage"] = @"en";
    arguments[@"translationProvider"] = @"ollama";
    arguments[@"learningEnabled"] = @NO;
    [defaults setVolatileDomain:arguments forName:NSArgumentDomain];
    @try {
        Composition *c = [Composition new];
        NSMutableArray *commits = [NSMutableArray array];
        __block NSUInteger requests = 0;
        c.committed = ^(NSString *text) { [commits addObject:text]; };
        c.service = ^(NSString *text, TranslationCompletion done) { requests++; done(@"I am studying Japanese.", nil); };
        [c synchronizeModifiers:0];
        Check([c.inputModeDescription isEqual:@"English"], @"Idle mode hint contains only the language name");
        [c handlePhysicalKey:0 text:@"hello" modifiers:0];
        Check([commits.lastObject isEqual:@"hello"] && !c.hasEditingSession, @"English remains direct in the English/Japanese pair");
        [c handleModifiers:JapaneseFlags];
        Check([c.engine.language isEqual:@"ja"] && [c.inputModeDescription isEqual:@"Japanese"], @"Caps selects the Japanese engine with a short language hint");
        [commits removeAllObjects];
        Type(c, @"nihongo");
        Check(c.hasEditingSession && !commits.count && [c.engine.rawInput isEqual:@"nihongo"], @"Romaji stays in composition instead of leaking Latin letters into the host");
        Check([c.engine.preedit isEqual:@"にほんご"], @"Romaji displays its hiragana reading");
        Check(c.engine.preeditCaret == c.engine.preedit.length, @"The Japanese reading caret uses correct UTF-16 positions");
        if (![c.engine.preedit isEqual:@"にほんご"]) fprintf(stderr, "  nihongo preedit=%s candidates=%s\n", c.engine.preedit.UTF8String, c.engine.candidates.description.UTF8String);
        Check([c.inputModeDescription isEqual:@"Japanese"], @"The draft header stays concise while typing");
        Check(Choose(c, @"日本語") && [c.chinese isEqual:@"日本語"], @"The Japanese dictionary offers and confirms kanji");
        [c handlePhysicalKey:6 text:@"z" modifiers:JapaneseFlags | NSEventModifierFlagCommand];
        Check([c.engine.rawInput isEqual:@"nihongo"] && !c.chinese.length && [c.engine.language isEqual:@"ja"], @"Undo restores Japanese candidates in the Japanese engine");
        [c handlePhysicalKey:6 text:@"z" modifiers:JapaneseFlags | NSEventModifierFlagCommand | NSEventModifierFlagShift];
        Check([c.chinese isEqual:@"日本語"] && !c.engine.preedit.length, @"Redo restores the selected Japanese word");
        [c handlePhysicalKey:36 text:@"\r" modifiers:JapaneseFlags];
        Check([commits.lastObject isEqual:@"日本語"] && !c.hasEditingSession && [c.inputLanguage isEqual:@"ja"], @"Enter inserts Japanese and keeps the physical keyboard language");

        for (NSArray *fixture in @[@[@"konnichiha", @"こんにちは"], @[@"tesuto", @"テスト"], @[@"gakkou", @"学校"], @[@"ko-hi-", @"コーヒー"], @[@"shin'you", @"信用"]]) {
            Type(c, fixture[0]);
            Check([c.engine.candidates containsObject:fixture[1]], [@"Common word is available on the first candidate page: " stringByAppendingString:fixture[0]]);
            BOOL found = Choose(c, fixture[1]);
            Check(found && [c.chinese isEqual:fixture[1]], [@"Japanese conversion: " stringByAppendingString:fixture[0]]);
            if (!found) fprintf(stderr, "  preedit=%s candidates=%s\n", c.engine.preedit.UTF8String, c.engine.candidates.description.UTF8String);
            [c cancel];
        }
        for (NSArray *part in @[@[@"nihongo", @"日本語"], @[@"wo", @"を"], @[@"benkyou", @"勉強"], @[@"shite", @"して"], @[@"imasu", @"います"]]) {
            Type(c, part[0]);
            Check([c.engine.candidates containsObject:part[1]], [@"Sentence segment is available without paging: " stringByAppendingString:part[1]]);
            BOOL found = Choose(c, part[1]);
            Check(found, [@"Sentence segment: " stringByAppendingString:part[1]]);
            if (!found) fprintf(stderr, "  segment=%s preedit=%s candidates=%s\n", [part[0] UTF8String], c.engine.preedit.UTF8String, c.engine.candidates.description.UTF8String);
        }
        Check([c.chinese isEqual:@"日本語を勉強しています"], @"Confirmed Japanese phrases form one editable sentence");
        Pump(0.45);
        Check(c.ready && requests > 0 && [c.translationTargetLanguage isEqual:@"en"], @"Japanese sentence translation targets the other configured language");
        [c handlePhysicalKey:48 text:@"\t" modifiers:JapaneseFlags];
        Check([commits.lastObject isEqual:@"I am studying Japanese."] && !c.hasEditingSession, @"Tab inserts the ready sentence translation");

        Type(c, @"nihongo");
        [c handlePhysicalKey:124 text:@"" modifiers:JapaneseFlags];
        NSString *selected = c.engine.candidates[c.engine.highlighted];
        NSUInteger before = commits.count;
        [c handleModifiers:0];
        Check(commits.count == before + 1 && [commits.lastObject isEqual:selected] && c.inputEnglish, @"Caps confirms the highlighted Japanese candidate before switching to English");
        if (![commits.lastObject isEqual:selected]) fprintf(stderr, "  selected=%s committed=%s\n", selected.UTF8String, [commits.lastObject UTF8String]);
        [c handlePhysicalKey:0 text:@"ok" modifiers:0];
        Check([commits.lastObject isEqual:@"ok"] && !c.hasEditingSession, @"English remains direct after the Japanese panel closes");

        [c handleModifiers:JapaneseFlags];
        Type(c, @"nihongo"); Choose(c, @"日本語");
        [c handlePhysicalKey:43 text:@"," modifiers:JapaneseFlags];
        [c handlePhysicalKey:47 text:@"." modifiers:JapaneseFlags];
        Check([c.chinese isEqual:@"日本語、。"], @"Japanese uses its own comma and full stop");
        [c cancel];
        Type(c, @"hello");
        [c handlePhysicalKey:36 text:@"\r" modifiers:JapaneseFlags];
        Check([c.chinese isEqual:@"hello"] && !c.engine.preedit.length, @"Return retains the input method's raw-letter confirmation for mixed-language text");
        [c cancel];
        c.engine.learningEnabled = YES;
        Type(c, @"nihongo");
        Check(Choose(c, @"日本語") && [c.engine.language isEqual:@"ja"], @"Enabling personal learning keeps the Japanese schema selected");
        [c cancel];
        c.engine.learningEnabled = NO;
        Type(c, @"nihongo");
        Check(Choose(c, @"日本語") && [c.engine.language isEqual:@"ja"], @"Disabling learning retains Japanese base candidates");
        [c cancel];
    } @finally { [defaults setVolatileDomain:original forName:NSArgumentDomain]; }
    printf("Japanese: %lu checks, %lu failures\n", checks, failures);
    return failures ? 1 : 0;
}
