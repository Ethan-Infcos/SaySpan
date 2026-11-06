#import <Foundation/Foundation.h>

// English source strings are stable keys; model prompts and user text are never localized.
NSString *L(NSString *key);
NSString *AppDisplayName(void);
NSString *ReadInterfaceLanguage(void);
NSString *ResolveInterfaceLanguage(NSString *preference, NSArray<NSString *> *preferredLanguages);
NSString *CurrentInterfaceLanguage(void);
int RunLocalizationTests(void);
