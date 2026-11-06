#import "SettingsController.h"
#import "ModelProvider.h"

static int checks, failures;
static void CheckSettings(BOOL condition, NSString *message) {
    checks++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); }
}

// Replace model persistence so these tests never access personal credentials or settings.
@interface SettingsModelFixture : ModelPreferencesView
@property(nonatomic) BOOL rejectSave;
@end
@implementation SettingsModelFixture
- (BOOL)savePreferences:(NSError **)error {
    if (_rejectSave && error)
        *error = [NSError errorWithDomain:@"SettingsFixture" code:1 userInfo:nil];
    return !_rejectSave;
}
@end

static void ChangeSwitch(NSButton *button, BOOL on) {
    button.state = on ? NSControlStateValueOn : NSControlStateValueOff;
    CheckSettings(button.target && button.action && [NSApp sendAction:button.action to:button.target from:button],
                  @"The selection switch has a working action");
}

int RunSettingsTests(void) {
    checks = failures = 0;
    NSString *suite = [@"local.vokira.settings-test." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:suite];
    NSDictionary *original = [NSUserDefaults.standardUserDefaults persistentDomainForName:@"local.inputmethod.DualLineIME"] ?: @{};
    ModelSettingsController *controller;
    @try {
        controller = [[ModelSettingsController alloc] initWithPreferences:preferences];
        SettingsModelFixture *model = [SettingsModelFixture new];
        [controller setValue:model forKey:@"modelPreferences"];
        NSButton *enabled = [controller valueForKey:@"selectionEnabled"];
        NSButton *automatic = [controller valueForKey:@"selectionAutomatic"];
        CheckSettings(enabled.state == NSControlStateValueOn && automatic.state == NSControlStateValueOff,
                      @"New installations enable selection translation and require a click by default");
        CheckSettings(![preferences objectForKey:@"selectionTranslationEnabled"] && ![preferences objectForKey:@"selectionTranslationAutomatic"],
                      @"Opening Settings does not write defaults");

        ChangeSwitch(enabled, NO);
        CheckSettings(![preferences boolForKey:@"selectionTranslationEnabled"], @"Disabling selection translation persists without Save");
        ChangeSwitch(enabled, YES);
        CheckSettings([preferences boolForKey:@"selectionTranslationEnabled"], @"Enabling selection translation persists without Save");
        ChangeSwitch(automatic, YES);
        CheckSettings([preferences boolForKey:@"selectionTranslationAutomatic"] && [preferences boolForKey:@"selectionTranslationEnabled"],
                      @"Automatic display persists independently without changing the enable switch");

        model.rejectSave = YES;
        NSError *error;
        CheckSettings(![controller savePreferences:&error] && [error.domain isEqual:@"SettingsFixture"],
                      @"Invalid model settings still reject the general Save action");
        CheckSettings([preferences boolForKey:@"selectionTranslationEnabled"] && [preferences boolForKey:@"selectionTranslationAutomatic"],
                      @"Model validation cannot discard the applied selection switches");

        NSTextView *prompt = [controller valueForKey:@"translationPrompt"];
        prompt.string = @"Unsaved translation instructions";
        [preferences setBool:NO forKey:@"selectionTranslationAutomatic"];
        [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:preferences];
        CheckSettings(automatic.state == NSControlStateValueOff, @"Popup preference changes refresh the open Settings checkbox");
        CheckSettings([prompt.string isEqual:@"Unsaved translation instructions"], @"Preference refresh preserves unrelated unsaved edits");
        [preferences setBool:NO forKey:@"selectionTranslationEnabled"];
        [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:preferences];
        CheckSettings(enabled.state == NSControlStateValueOff, @"External enable changes refresh the open Settings checkbox");

        // Model a stale open form at the moment the user saves unrelated settings.
        enabled.state = automatic.state = NSControlStateValueOn;
        model.rejectSave = NO;
        CheckSettings([controller savePreferences:NULL], @"Valid model settings allow the general Save action");
        CheckSettings(![preferences boolForKey:@"selectionTranslationEnabled"] && ![preferences boolForKey:@"selectionTranslationAutomatic"],
                      @"Saving unrelated settings cannot overwrite newer selection preferences");
        CheckSettings(enabled.state == NSControlStateValueOff && automatic.state == NSControlStateValueOff,
                      @"The saved form reflects the actual selection preferences");

        // A delayed cross-process notification is also covered by the existing refresh timer.
        enabled.state = automatic.state = NSControlStateValueOn;
        [controller refreshSelectionPreferences];
        CheckSettings(enabled.state == NSControlStateValueOff && automatic.state == NSControlStateValueOff,
                      @"Polling refresh repairs stale checkboxes without requiring a notification");
        ChangeSwitch(enabled, YES);
        ChangeSwitch(automatic, YES);
        [NSApp sendAction:NSSelectorFromString(@"cancel:") to:controller from:nil];
        CheckSettings([preferences boolForKey:@"selectionTranslationEnabled"] && [preferences boolForKey:@"selectionTranslationAutomatic"],
                      @"Cancel preserves immediately applied selection preferences");
        controller = [[ModelSettingsController alloc] initWithPreferences:preferences];
        enabled = [controller valueForKey:@"selectionEnabled"];
        automatic = [controller valueForKey:@"selectionAutomatic"];
        CheckSettings(enabled.state == NSControlStateValueOn && automatic.state == NSControlStateValueOn,
                      @"Reopening Settings reloads both persisted switches");
        NSDictionary *current = [NSUserDefaults.standardUserDefaults persistentDomainForName:@"local.inputmethod.DualLineIME"] ?: @{};
        CheckSettings([original isEqual:current], @"Settings tests leave the user's complete preference domain unchanged");
        printf("%d settings checks, %d failures\n", checks, failures);
        return failures ? 1 : 0;
    } @finally {
        [controller close];
        controller = nil;
        [preferences removePersistentDomainForName:suite];
    }
}
