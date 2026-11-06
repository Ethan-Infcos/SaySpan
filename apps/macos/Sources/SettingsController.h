#import <Cocoa/Cocoa.h>

@interface ModelSettingsController : NSWindowController <NSWindowDelegate>
- (instancetype)initWithPreferences:(NSUserDefaults *)preferences;
- (void)present;
- (void)refreshSelectionPreferences;
- (BOOL)savePreferences:(NSError **)error;
@end

int RunSettingsTests(void);
