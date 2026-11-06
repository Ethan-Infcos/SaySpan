#import "Core.h"
#import "SelectionTranslation.h"
#import <NaturalLanguage/NaturalLanguage.h>

static int checks, failures;
static void Check(BOOL condition, NSString *message) {
    checks++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); }
}
static void Pump(NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (end.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
static NSString *Instruction(NSString *text, NSString *source, NSString *target) {
    NSURLRequest *request = MakeTranslationRequestForLanguages(text, source, target);
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL];
    Check([body[@"messages"][1][@"content"] isEqual:text], @"Multilingual source text is preserved in its own message");
    return body[@"messages"][0][@"content"];
}

static void TestAutomaticSelection(NSUserDefaults *preferences, NSMutableDictionary *arguments) {
    arguments[@"firstInputLanguage"] = @"en";
    arguments[@"secondInputLanguage"] = @"fr";
    arguments[@"selectionTranslationTarget"] = @"zh";
    arguments[@"lastInputLanguage"] = @"ja";
    [preferences setVolatileDomain:arguments forName:NSArgumentDomain];
    Check([ReadSelectionTranslationTarget() isEqual:@"auto"], @"Legacy fixed targets no longer bypass the shared language pair");
    Check([TranslationTargetForText(@"We will discuss the proposal tomorrow.", @"auto") isEqual:@"fr"], @"English in an English/French pair translates into French regardless of input memory");
    Check([TranslationTargetForText(@"Nous allons discuter de la proposition demain.", @"auto") isEqual:@"en"], @"French in the same pair translates back into English");
    SelectionTranslation *selection = [SelectionTranslation new];
    TextSelection *fixture = [TextSelection new];
    fixture.text = @"See you tomorrow."; fixture.identifier = @"automatic-direction"; fixture.processID = getpid();
    NSMutableArray *pending = [NSMutableArray array];
    selection.service = ^NSURLSessionDataTask *(NSString *text, NSString *target, TranslationCompletion done) {
        [pending addObject:[done copy]]; return nil;
    };
    [selection observeSelection:fixture];
    [selection translateWithPreference:ReadSelectionTranslationTarget()];
    Check([selection.sourceLanguage isEqual:@"auto"] && [selection.target isEqual:@"fr"], @"Selection snapshots the detected direction while retaining mixed-source recognition");
    arguments[@"secondInputLanguage"] = @"ja";
    [preferences setVolatileDomain:arguments forName:NSArgumentDomain];
    Check([selection.target isEqual:@"fr"], @"Changing the pair cannot relabel a running request");
    [selection translateWithPreference:@"auto"];
    Check([selection.target isEqual:@"ja"], @"Retry snapshots the updated pair");
    ((TranslationCompletion)pending[0])(@"À demain.", nil); Pump(0.02);
    Check(selection.loading && !selection.result.length, @"Late output for the previous pair is discarded");
    ((TranslationCompletion)pending[1])(@"また明日。", nil); Pump(0.02);
    Check([selection.result isEqual:@"また明日。"] && [ReadLastInputLanguage() isEqual:@"ja"], @"Selection output does not rewrite source-language memory");
    [selection dismiss];
}

int RunTranslationTests(BOOL live) {
    NSUserDefaults *preferences = NSUserDefaults.standardUserDefaults;
    NSDictionary *original = [preferences volatileDomainForName:NSArgumentDomain];
    NSMutableDictionary *arguments = [original mutableCopy];
    @try {
        arguments[@"translationSourceLanguage"] = @42;
        arguments[@"translationTargetLanguage"] = @"auto";
        arguments[@"translationPrompt"] = @"";
        [preferences setVolatileDomain:arguments forName:NSArgumentDomain];
        Check([ReadTranslationSourceLanguage() isEqual:@"auto"] && [ReadTranslationTargetLanguage() isEqual:@"en"], @"Invalid stored languages safely fall back to automatic source and English target");
        NSDictionary *names = @{@"zh":@"Simplified Chinese", @"zh-Hant":@"Traditional Chinese", @"en":@"English", @"ja":@"Japanese", @"ko":@"Korean", @"fr":@"French", @"de":@"German", @"es":@"Spanish", @"pt":@"Portuguese", @"it":@"Italian", @"ru":@"Russian", @"ar":@"Arabic", @"hi":@"Hindi", @"th":@"Thai", @"vi":@"Vietnamese", @"id":@"Indonesian"};
        Check(TranslationLanguages().count == names.count && ![TranslationLanguages() containsObject:@"auto"], @"Targets are explicit languages only");
        NSString *sample = @"你好, bonjour!\nKeep `API(\"x\")` and 👨‍👩‍👧‍👦.";
        for (NSString *code in TranslationLanguages()) {
            NSString *system = Instruction(sample, @"auto", code);
            Check([system hasPrefix:[NSString stringWithFormat:@"Translate the user's text into %@.", names[code]]] && [system containsString:@"Automatically identify"], @"Every target reaches the request without defaulting to English");
            Check(TranslationLanguageBadge(code).length <= 2 && ![TranslationLanguageName(code) isEqual:L(@"Detect automatically")], @"All languages have compact badges and explicit display names");
        }
        arguments[@"translationSourceLanguage"] = @"es";
        arguments[@"translationTargetLanguage"] = @"ja";
        arguments[@"translationPrompt"] = @"Preserve all dates.\nUse a polite tone.";
        [preferences setVolatileDomain:arguments forName:NSArgumentDomain];
        NSString *system = Instruction(sample, ReadTranslationSourceLanguage(), ReadTranslationTargetLanguage());
        Check([system containsString:@"specified source language is Spanish"] && [system hasPrefix:@"Translate the user's text into Japanese."] && [system hasSuffix:arguments[@"translationPrompt"]], @"Explicit source, target and custom prompt coexist");
        Check([system containsString:@"already in the target language unchanged"], @"Already-target passages are preserved by the request rules");

        arguments[@"firstInputLanguage"] = @"zh";
        arguments[@"secondInputLanguage"] = @"ja";
        [preferences setVolatileDomain:arguments forName:NSArgumentDomain];
        Composition *composition = [Composition new];
        composition.directEnglish = NO;
        composition.engine.learningEnabled = NO;
        NSMutableArray *pending = [NSMutableArray array];
        composition.service = ^(NSString *text, TranslationCompletion done) { [pending addObject:[done copy]]; };
        composition.pasteText = ^{ return @"会议是明天下午三点。"; };
        [composition handleKey:0 text:@"n" modifiers:0];
        [composition handleKey:0 text:@"a" modifiers:NSEventModifierFlagCommand];
        [composition handleKey:9 text:@"v" modifiers:NSEventModifierFlagCommand];
        Pump(0.45);
        Check(pending.count == 1 && [composition.translationSourceLanguage isEqual:@"auto"] && [composition.translationTargetLanguage isEqual:@"ja"], @"Composition captures the configured direction when scheduling");
        arguments[@"secondInputLanguage"] = @"fr";
        [preferences setVolatileDomain:arguments forName:NSArgumentDomain];
        Check([composition.translationTargetLanguage isEqual:@"ja"], @"Changing settings cannot relabel an in-flight translation");
        [composition retry]; Pump(0.45);
        Check(pending.count == 2 && [composition.translationTargetLanguage isEqual:@"fr"], @"Retry applies the new target without changing the draft");
        if (pending.count == 2) {
            ((TranslationCompletion)pending[0])(@"古い訳文", nil); Pump(0.02);
            Check(!composition.english.length && !composition.ready, @"A late response for the previous direction is rejected");
            ((TranslationCompletion)pending[1])(@"La réunion est demain à 15 h.", nil); Pump(0.02);
            Check(composition.ready && [composition.english containsString:@"réunion"], @"The latest target becomes ready");
            __block NSString *committed;
            composition.committed = ^(NSString *text) { committed = text; };
            [composition handleKey:48 text:@"\t" modifiers:0];
            Check([committed isEqual:@"La réunion est demain à 15 h."], @"Tab commits the configured target language");
        }
        [composition cancel];
        arguments[@"secondInputLanguage"] = @"ja";
        [preferences setVolatileDomain:arguments forName:NSArgumentDomain];
        [composition handleKey:0 text:@"n" modifiers:0];
        Check([composition.translationTargetLanguage isEqual:@"ja"] && composition.engine.preedit.length, @"A reused controller refreshes its badge before the first candidate is confirmed");
        [composition cancel];
        arguments[@"secondInputLanguage"] = @"fr";
        [preferences setVolatileDomain:arguments forName:NSArgumentDomain];

        SelectionTranslation *selection = [SelectionTranslation new];
        TextSelection *fixture = [TextSelection new];
        fixture.text = @"Nous allons discuter du projet demain."; fixture.identifier = @"translation-test"; fixture.processID = getpid();
        __block NSString *requestedTarget;
        selection.service = ^NSURLSessionDataTask *(NSString *text, NSString *target, TranslationCompletion done) {
            requestedTarget = target; done(@"Hola.", nil); return nil;
        };
        [selection observeSelection:fixture];
        [selection translateWithPreference:@"configured"]; Pump(0.02);
        Check([selection.sourceLanguage isEqual:@"auto"] && [requestedTarget isEqual:@"zh"] && [selection.result isEqual:@"Hola."], @"Automatic translation detects French and selects the other configured language");
        [selection translateWithPreference:@"ja"]; Pump(0.02);
        Check([selection.sourceLanguage isEqual:@"auto"] && [requestedTarget isEqual:@"ja"], @"A separate selection target keeps automatic source detection");
        Check([TranslationTargetForText(@"我们明天见面。", @"auto") isEqual:@"fr"] && [TranslationTargetForText(@"Nous allons nous retrouver demain.", @"auto") isEqual:@"zh"], @"Automatic translation works in both directions for the configured pair");
        [selection dismiss];
        TestAutomaticSelection(preferences, arguments);

        if (live) {
            arguments[@"translationPrompt"] = @"";
            [preferences setVolatileDomain:arguments forName:NSArgumentDomain];
            NSArray *fixtures = @[
                @[@"请明天上午十点开会，不要发送邀请。", @"auto", @"ja", @"ja"],
                @[@"请明天上午十点开会。Keep the API name unchanged.", @"auto", @"fr", @"fr"],
                @[@"La reunión es mañana a las 15:00. No envíes las invitaciones todavía.", @"es", @"en", @"en"],
                @[@"La réunion est demain à dix heures. N'envoyez pas encore les invitations.", @"fr", @"zh", @"zh-Hans"]
            ];
            for (NSArray *fixture in fixtures) {
                __block BOOL done = NO;
                __block NSString *result;
                __block NSError *failure;
                NSURLSessionDataTask *task = TranslateTextWithLanguages(fixture[0], fixture[1], fixture[2], ^(NSString *text, NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{ result = text; failure = error; done = YES; });
                });
                NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:95];
                while (!done && deadline.timeIntervalSinceNow > 0) Pump(0.03);
                if (!done) [task cancel];
                Check(done && !failure && result.length, @"Local Ollama returns a multilingual translation");
                Check([[NLLanguageRecognizer dominantLanguageForString:result ?: @""] isEqual:fixture[3]], @"Live output is in the requested target language");
                if ([fixture[2] isEqual:@"fr"])
                    Check([result containsString:@"API"] && ![result containsString:@"Keep the API name unchanged"], @"Mixed-language output translates the second sentence and retains its API name");
                if ([fixture[2] isEqual:@"en"])
                    Check([result.lowercaseString containsString:@"tomorrow"] && [result.lowercaseString containsString:@"invitations"] && ([result.lowercaseString containsString:@"don't"] || [result.lowercaseString containsString:@"not"]), @"Spanish-to-English output retains the date and negated invitation instruction");
                printf("Live %s -> %s: %s\n", [fixture[1] UTF8String], [fixture[2] UTF8String], result.UTF8String ?: "(failed)");
                fflush(stdout);
            }
        }
    } @finally { [preferences setVolatileDomain:original forName:NSArgumentDomain]; }
    printf("%d multilingual checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
