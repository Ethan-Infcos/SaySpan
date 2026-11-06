#import "Core.h"
#import "ModelProvider.h"

static NSUInteger checks, failures;
static void CheckLocalization(BOOL condition, NSString *message) {
    checks++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); }
}
static NSDictionary *StringsForLanguage(NSString *language) {
    NSString *directory = [NSBundle.mainBundle pathForResource:language ofType:@"lproj"];
    NSData *data = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"Localizable.strings"]];
    return data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL] : nil;
}
static NSArray *Placeholders(NSString *text) {
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"%(?:[0-9]+\\$)?(?:l|ll)?[@diuf]" options:0 error:NULL];
    NSMutableArray *result = [NSMutableArray array];
    for (NSTextCheckingResult *match in [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)])
        [result addObject:[text substringWithRange:match.range]];
    return result;
}
int RunLocalizationTests(void) {
    checks = failures = 0;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *original = [defaults volatileDomainForName:NSArgumentDomain];
    NSMutableDictionary *arguments = original.mutableCopy;
    CheckLocalization([ResolveInterfaceLanguage(@"system", @[@"en-US", @"zh-Hans"]) isEqual:@"en"], @"English system preference wins over Chinese fallback");
    CheckLocalization([ResolveInterfaceLanguage(@"system", @[@"zh-Hans-CN", @"en"]) isEqual:@"zh-Hans"], @"Simplified Chinese system preference resolves its regional variant");
    CheckLocalization([ResolveInterfaceLanguage(@"system", @[@"de-DE", @"en"]) isEqual:@"en"], @"Unsupported system language falls back to English");
    CheckLocalization([ResolveInterfaceLanguage(@"system", @[]) isEqual:@"en"], @"Missing language preferences fall back to English");
    CheckLocalization([ResolveInterfaceLanguage(@"zh-Hans", @[@"en-US"]) isEqual:@"zh-Hans"], @"Explicit Chinese overrides an English system");
    CheckLocalization([ResolveInterfaceLanguage(@"invalid", @[@"en-US"]) isEqual:@"en"], @"Invalid app preferences follow the system");
    NSDictionary *english = StringsForLanguage(@"en"), *chinese = StringsForLanguage(@"zh-Hans");
    CheckLocalization(english.count > 150 && [NSSet setWithArray:english.allKeys].count == english.count &&
        [[NSSet setWithArray:english.allKeys] isEqual:[NSSet setWithArray:chinese.allKeys]], @"Both shipped catalogs have complete matching keys");
    for (NSString *key in english) {
        CheckLocalization([english[key] isEqual:key] && [chinese[key] length] && [Placeholders(key) isEqual:Placeholders(chinese[key])],
                          [@"Nonempty translation and matching placeholders: " stringByAppendingString:key]);
    }
    NSDictionary *referenceRequest;
    for (NSString *language in @[@"en", @"zh-Hans"]) {
        arguments[@"interfaceLanguage"] = language;
        [defaults setVolatileDomain:arguments forName:NSArgumentDomain];
        CheckLocalization([CurrentInterfaceLanguage() isEqual:language], @"Language selection resolves at runtime");
        CheckLocalization([L(@"Settings…") isEqual:[language isEqual:@"en"] ? @"Settings…" : @"设置…"], @"Runtime strings use the selected resource bundle");
        CheckLocalization([L(@"future missing key") isEqual:@"future missing key"], @"A missing translation keeps its English source text");
        NSString *title = [AppDisplayName() stringByAppendingString:[language isEqual:@"en"] ? @" Settings" : @"设置"];
        CheckLocalization([L(@"{appName} Settings") isEqual:title], @"Localized window titles expand the shared brand");
        CheckLocalization([L(@"{appName} missing key") isEqual:[AppDisplayName() stringByAppendingString:@" missing key"]], @"Fallback strings also expand the shared brand");
        NSString *localizedPath = [[NSBundle.mainBundle pathForResource:language ofType:@"lproj"] stringByAppendingPathComponent:@"InfoPlist.strings"];
        NSDictionary *names = [NSDictionary dictionaryWithContentsOfFile:localizedPath];
        for (NSString *name in names.allValues)
            CheckLocalization([name isEqual:AppDisplayName()], @"Localized input-source names match the shared brand");
        for (NSString *code in TranslationLanguages())
            CheckLocalization(TranslationLanguageBadge(code).length <= 2 && TranslationLanguageName(code).length > 0, @"All language badges stay compact in both UI languages");
        NSDictionary *request = [NSJSONSerialization JSONObjectWithData:MakeTranslationRequestForLanguages(@"你好\nHello", @"auto", @"ja").HTTPBody options:0 error:NULL];
        if (referenceRequest) CheckLocalization([request isEqual:referenceRequest], @"Changing interface language never changes translation prompts or user text");
        referenceRequest = request;
        CheckLocalization([TranslationRequestError(401, YES).localizedDescription isEqual:L(@"The API key is invalid or cannot access this model. Check Models.")], @"Provider errors are localized");
        for (NSString *name in @[@"CFBundleName", @"CFBundleDisplayName"])
            CheckLocalization([[NSBundle.mainBundle objectForInfoDictionaryKey:name] isEqual:AppDisplayName()], @"Public bundle names use the shared product name");
    }
    [defaults setVolatileDomain:original forName:NSArgumentDomain];
    printf("Localization: %lu checks, %lu failures\n", checks, failures);
    return failures ? 1 : 0;
}
