#import "Core.h"
#import "SelectionTranslation.h"
#import "ModelProvider.h"
#import "SettingsController.h"
#import "InputSourceRegistration.h"
#import <InputMethodKit/InputMethodKit.h>
#import <Carbon/Carbon.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSString *option = argc > 1 ? @(argv[1]) : @"";
        if ([option isEqual:@"--refresh-input-source-cache"]) return RefreshKeyboardSettingsCache();
        if ([option isEqual:@"--localization-test"]) return RunLocalizationTests();
        if ([@[@"--self-test", @"--live-test", @"--translation-test", @"--translation-live-test", @"--selection-test", @"--selection-live-test"] containsObject:option]) {
            // Regression fixtures must never inherit a user's paid online destination.
            NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
            NSMutableDictionary *arguments = [[defaults volatileDomainForName:NSArgumentDomain] mutableCopy];
            arguments[@"translationProvider"] = @"ollama";
            arguments[@"firstInputLanguage"] = @"en";
            arguments[@"secondInputLanguage"] = @"zh";
            [defaults setVolatileDomain:arguments forName:NSArgumentDomain];
        }
        if ([@[@"--self-test", @"--live-test", @"--learning-test-write", @"--learning-test-read", @"--candidate-preview", @"--sentence-preview"] containsObject:option]) {
            // Chinese editing fixtures use Caps off; production always follows the keyboard.
            NSMutableDictionary *arguments = [[NSUserDefaults.standardUserDefaults volatileDomainForName:NSArgumentDomain] mutableCopy];
            arguments[@"firstInputLanguage"] = @"zh";
            arguments[@"secondInputLanguage"] = @"en";
            [NSUserDefaults.standardUserDefaults setVolatileDomain:arguments forName:NSArgumentDomain];
        }
        if ([option isEqual:@"--provider-test"]) return RunModelProviderTests();
        if ([option isEqual:@"--settings-test"]) return RunSettingsTests();
        if ([option isEqual:@"--settings"]) {
            ShowSettings();
            [NSApp run];
            return 0;
        }
        if ([option isEqual:@"--selection-preview"] || [option isEqual:@"--selection-result-preview"]) {
            ShowSelectionTranslationPreview();
            [NSApp run];
            return 0;
        }
        if ([option isEqual:@"--selection-test"] || [option isEqual:@"--selection-live-test"])
            return RunSelectionTranslationTests([option isEqual:@"--selection-live-test"]);
        if ([option isEqual:@"--register"]) {
            OSStatus status = TISRegisterInputSource((__bridge CFURLRef)[NSBundle mainBundle].bundleURL);
            printf("TISRegisterInputSource: %d\n", (int)status);
            return status == noErr ? 0 : 1;
        }
        if ([option isEqual:@"--list"]) {
            NSDictionary *filter = @{(__bridge NSString *)kTISPropertyBundleID:@"local.inputmethod.DualLineIME"};
            NSArray *sources = CFBridgingRelease(TISCreateInputSourceList((__bridge CFDictionaryRef)filter, true));
            for (id source in sources) {
                TISInputSourceRef ref = (__bridge TISInputSourceRef)source;
                NSString *identifier = (__bridge NSString *)TISGetInputSourceProperty(ref, kTISPropertyInputSourceID);
                NSString *name = (__bridge NSString *)TISGetInputSourceProperty(ref, kTISPropertyLocalizedName);
                NSNumber *enabled = (__bridge NSNumber *)TISGetInputSourceProperty(ref, kTISPropertyInputSourceIsEnabled);
                NSArray *languages = (__bridge NSArray *)TISGetInputSourceProperty(ref, kTISPropertyInputSourceLanguages);
                printf("%s | %s | enabled=%s | languages=%s\n", identifier.UTF8String, name.UTF8String, enabled.boolValue ? "yes" : "no", languages.description.UTF8String);
            }
            return sources.count ? 0 : 1;
        }
        NSError *error;
        BOOL deploy = [option isEqual:@"--deploy"];
        if (!StartRime(deploy, &error)) {
            fprintf(stderr, "Pinyin engine initialization failed: %s\n", error.localizedDescription.UTF8String ?: "unknown error");
            return 1;
        }
        if (deploy) { StopRime(); return 0; }
        if ([option isEqual:@"--typing-engine-test"]) {
            int result = RunTypingEngineTests();
            StopRime();
            return result;
        }
        if ([option isEqual:@"--japanese-test"]) {
            int result = RunJapaneseTests();
            StopRime();
            return result;
        }
        if ([option isEqual:@"--language-pair-test"]) {
            int result = RunLanguagePairTests();
            StopRime();
            return result;
        }
        if ([option isEqual:@"--translation-test"] || [option isEqual:@"--translation-live-test"]) {
            int result = RunTranslationTests([option isEqual:@"--translation-live-test"]);
            StopRime();
            return result;
        }
        if ([option isEqual:@"--learning-test-write"] || [option isEqual:@"--learning-test-read"]) {
            int result = RunLearningTests([option isEqual:@"--learning-test-read"]);
            StopRime();
            return result;
        }
        if ([option isEqual:@"--self-test"] || [option isEqual:@"--live-test"]) {
            int result = RunSelfTests([option isEqual:@"--live-test"]);
            StopRime();
            return result;
        }
        if ([option isEqual:@"--candidate-preview"] || [option isEqual:@"--sentence-preview"]) {
            ShowCandidatePreview();
            [NSApp run];
            StopRime();
            return 0;
        }
        IMKServer *server = [[IMKServer alloc] initWithName:@"DualLineIME_Connection" bundleIdentifier:@"local.inputmethod.DualLineIME"];
        if (!server) { fprintf(stderr, "Cannot start InputMethodKit server.\n"); return 1; }
        StartSelectionTranslation();
        if ([option isEqual:@"--show-settings"]) ShowSettings();
        [NSApp run];
        (void)server;
    }
    return 0;
}
