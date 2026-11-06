#import "Localization.h"

NSString *AppDisplayName(void) {
    // The build resolves the shared brand into bundle metadata for every locale.
    return NSBundle.mainBundle.infoDictionary[@"CFBundleName"] ?: NSProcessInfo.processInfo.processName;
}

NSString *ReadInterfaceLanguage(void) {
    id saved = [NSUserDefaults.standardUserDefaults objectForKey:@"interfaceLanguage"];
    return [@[@"en", @"zh-Hans"] containsObject:saved ?: @""] ? saved : @"system";
}

NSString *ResolveInterfaceLanguage(NSString *preference, NSArray<NSString *> *preferredLanguages) {
    NSArray *supported = @[@"en", @"zh-Hans"];
    if ([supported containsObject:preference ?: @""]) return preference;
    return [NSBundle preferredLocalizationsFromArray:supported forPreferences:preferredLanguages ?: @[]].firstObject ?: @"en";
}

NSString *CurrentInterfaceLanguage(void) {
    return ResolveInterfaceLanguage(ReadInterfaceLanguage(), NSLocale.preferredLanguages);
}

NSString *L(NSString *key) {
    static NSDictionary<NSString *, NSBundle *> *bundles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *available = [NSMutableDictionary dictionary];
        for (NSString *language in @[@"en", @"zh-Hans"]) {
            NSString *path = [NSBundle.mainBundle pathForResource:language ofType:@"lproj"];
            NSBundle *bundle = path ? [NSBundle bundleWithPath:path] : nil;
            if (bundle) available[language] = bundle;
        }
        bundles = available.copy;
    });
    NSString *localized = [bundles[CurrentInterfaceLanguage()] localizedStringForKey:key value:key table:nil] ?: key;
    return [localized stringByReplacingOccurrencesOfString:@"{appName}" withString:AppDisplayName()];
}
