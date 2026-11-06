#import "Core.h"

BOOL UsesOnlineTranslation(void);
NSString *ReadOnlineBaseURL(void);
NSString *ReadOnlineModel(void);
NSString *ReadOnlineReasoning(void);
NSString *NormalizeOnlineBaseURL(NSString *value, NSError **error);
BOOL ValidOnlineModel(NSString *model);
NSArray<NSString *> *OnlineReasoningOptions(void);
NSString *EffectiveOnlineReasoning(NSString *model, NSString *selection);
NSString *OnlineReasoningExplanation(NSString *model, NSString *selection);
NSError *ModelProviderError(NSInteger code, NSString *message);
BOOL HasOnlineAPIKey(NSString *baseURL);
NSString *ReadOnlineAPIKey(NSString *baseURL, BOOL allowInteraction, NSError **error);
BOOL SaveOnlineAPIKey(NSString *baseURL, NSString *key, NSError **error);
BOOL DeleteOnlineAPIKey(NSString *baseURL, NSError **error);
NSURLRequest *MakeOnlineTranslationRequest(NSString *text, NSString *source, NSString *target, NSString *baseURL, NSString *model, NSString *key, NSString *reasoning, NSError **error);
NSURLRequest *MakeOnlineModelsRequest(NSString *baseURL, NSString *key, NSError **error);
NSArray<NSString *> *DecodeOnlineModels(NSData *data, NSError **error);
NSString *DecodeOnlineTranslation(NSData *data, NSInteger status);
NSError *TranslationRequestError(NSInteger status, BOOL online);
NSURLSession *ModelProviderSession(void);
NSURLSession *MakeModelProviderSession(NSURLSessionConfiguration *configuration);
NSURLSessionDataTask *RunTranslationRequestInSession(NSURLRequest *request, BOOL online, NSURLSession *session, TranslationCompletion completion);
NSURLSessionDataTask *RunTranslationRequest(NSURLRequest *request, BOOL online, TranslationCompletion completion);
int RunModelProviderTests(void);

@interface ModelPreferencesView : NSView
- (void)loadPreferences;
- (BOOL)savePreferences:(NSError **)error;
- (void)cancelPending;
@end
