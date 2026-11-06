#import "ModelProvider.h"

static NSString *PreferenceString(NSString *key, NSString *fallback) {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:key];
    return [value isKindOfClass:NSString.class] ? value : fallback;
}
BOOL UsesOnlineTranslation(void) { return [PreferenceString(@"translationProvider", @"ollama") isEqual:@"online"]; }
NSString *ReadOnlineBaseURL(void) { return PreferenceString(@"onlineBaseURL", @"https://api.openai.com/v1"); }
NSString *ReadOnlineModel(void) { return PreferenceString(@"onlineModel", @""); }
NSArray<NSString *> *OnlineReasoningOptions(void) { return @[@"lowest", @"default", @"none", @"minimal", @"low", @"medium", @"high", @"xhigh", @"max"]; }
NSString *ReadOnlineReasoning(void) {
    NSString *value = PreferenceString(@"onlineReasoning", @"lowest");
    return [OnlineReasoningOptions() containsObject:value] ? value : @"lowest";
}
NSError *ModelProviderError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"DualLineIME.Provider" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}
NSString *NormalizeOnlineBaseURL(NSString *value, NSError **error) {
    NSString *text = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURLComponents *url = [NSURLComponents componentsWithString:text];
    BOOL loopback = [@[@"localhost", @"127.0.0.1", @"::1", @"[::1]"] containsObject:url.host.lowercaseString ?: @""];
    BOOL scheme = [url.scheme.lowercaseString isEqual:@"https"] || (loopback && [url.scheme.lowercaseString isEqual:@"http"]);
    if (!scheme || !url.host.length || url.user || url.password || url.query || url.fragment ||
        [text rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound || !url.URL) {
        if (error) *error = ModelProviderError(1, L(@"Enter a valid HTTPS API URL without credentials, keys, query parameters, or fragments. Local services may use HTTP."));
        return nil;
    }
    url.scheme = url.scheme.lowercaseString;
    url.host = url.host.lowercaseString;
    NSString *path = url.path;
    while ([path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
    for (NSString *suffix in @[@"/chat/completions", @"/models"])
        if ([path hasSuffix:suffix]) { path = [path substringToIndex:path.length - suffix.length]; break; }
    url.path = path;
    return url.URL.absoluteString;
}
BOOL ValidOnlineModel(NSString *model) {
    return model.length > 0 && model.length <= 256 &&
        [model rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location == NSNotFound &&
        [model rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
}
static BOOL ModelMatches(NSString *model, NSString *pattern) {
    return [model rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}
NSString *EffectiveOnlineReasoning(NSString *model, NSString *selection) {
    if ([selection isEqual:@"default"]) return nil;
    if (![selection isEqual:@"lowest"]) return [OnlineReasoningOptions() containsObject:selection] ? selection : nil;
    NSString *name = model.lowercaseString.lastPathComponent;
    // Conservative documented families only. Unknown aliases use the service default.
    if (ModelMatches(name, @"^(gpt-6\\.1-sol|gpt-6-astra|o3|o3-mini)(-[0-9]{4}-[0-9]{2}-[0-9]{2})?$")) return @"low";
    if (ModelMatches(name, @"^(gpt-6-sol|gpt-6-luna|gpt-5\\.2)(-[0-9]{4}-[0-9]{2}-[0-9]{2})?$")) return @"none";
    if (ModelMatches(name, @"^gpt-5(-mini|-nano)?(-[0-9]{4}-[0-9]{2}-[0-9]{2})?$")) return @"minimal";
    if (ModelMatches(name, @"^deepseek-(flash|v4-flash|v4-pro|chat)$")) return @"none";
    return nil;
}
NSString *OnlineReasoningExplanation(NSString *model, NSString *selection) {
    if (!model.length) return L(@"Choose a model to use its lowest supported effort, or select an effort manually.");
    NSString *effort = EffectiveOnlineReasoning(model, selection);
    if (effort) return [NSString stringWithFormat:L(@"Using: %@. Lower effort is usually faster for translation. Support depends on your provider."), effort];
    if ([selection isEqual:@"lowest"]) return L(@"The lowest effort for this model is unknown. Using the service default; you can choose manually. Use Service default for models without reasoning controls.");
    return L(@"Use the service default without a reasoning parameter. Suitable for models without reasoning controls.");
}
static NSMutableURLRequest *OnlineRequest(NSString *base, NSString *suffix, NSString *key, NSError **error) {
    base = NormalizeOnlineBaseURL(base, error);
    if (!base) return nil;
    if (!key.length || [key rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound || [key rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
        if (error) *error = ModelProviderError(2, L(@"Enter a valid API key in Models."));
        return nil;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[base stringByAppendingString:suffix]] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:90];
    [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    return request;
}
NSURLRequest *MakeOnlineTranslationRequest(NSString *text, NSString *source, NSString *target, NSString *baseURL, NSString *model, NSString *key, NSString *reasoning, NSError **error) {
    if (!ValidOnlineModel(model)) { if (error) *error = ModelProviderError(3, L(@"Enter a model ID or choose one from the online list.")); return nil; }
    NSMutableURLRequest *request = OnlineRequest(baseURL, @"/chat/completions", key, error);
    if (!request) return nil;
    NSDictionary *local = [NSJSONSerialization JSONObjectWithData:MakeTranslationRequestForLanguages(text, source, target).HTTPBody options:0 error:NULL];
    NSMutableDictionary *body = [@{@"model":model, @"stream":@NO, @"messages":local[@"messages"]} mutableCopy];
    NSString *effort = EffectiveOnlineReasoning(model, reasoning);
    if (effort) body[@"reasoning_effort"] = effort;
    // Omit temperature: several reasoning models reject non-default sampling parameters.
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];
    return request;
}
NSURLRequest *MakeOnlineModelsRequest(NSString *baseURL, NSString *key, NSError **error) {
    NSMutableURLRequest *request = OnlineRequest(baseURL, @"/models", key, error);
    request.timeoutInterval = 15;
    return request;
}
NSArray<NSString *> *DecodeOnlineModels(NSData *data, NSError **error) {
    id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    if (![json isKindOfClass:NSDictionary.class] || ![json[@"data"] isKindOfClass:NSArray.class]) {
        if (error) *error = ModelProviderError(4, L(@"The service returned an incompatible model list. You can still enter a model ID manually.")); return nil;
    }
    NSMutableSet *names = [NSMutableSet set];
    for (id entry in json[@"data"]) {
        id name = [entry isKindOfClass:NSDictionary.class] ? entry[@"id"] : nil;
        if ([name isKindOfClass:NSString.class] && ValidOnlineModel(name)) [names addObject:name];
        if (names.count >= 3000) break;
    }
    return [names.allObjects sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}
NSString *DecodeOnlineTranslation(NSData *data, NSInteger status) {
    if (status != 200 || !data) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    id choices = [json isKindOfClass:NSDictionary.class] ? json[@"choices"] : nil;
    id choice = [choices isKindOfClass:NSArray.class] && [choices count] ? choices[0] : nil;
    if (![choice isKindOfClass:NSDictionary.class]) return nil;
    if ([choice[@"finish_reason"] isEqual:@"length"] || [choice[@"finish_reason"] isEqual:@"content_filter"]) return nil;
    id message = choice[@"message"];
    id text = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
    if (![text isKindOfClass:NSString.class]) return nil;
    NSString *clean = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return clean.length ? clean : nil;
}
NSError *TranslationRequestError(NSInteger status, BOOL online) {
    if (!online) return ModelProviderError(status, status ? L(@"Local translation failed. Check Ollama and the selected model.") : L(@"Could not connect to local Ollama."));
    NSString *message = L(@"Online translation returned no complete result. Check Models or try again later.");
    if (status == 0) message = L(@"Could not connect to the online service. Check your network and API URL.");
    else if (status == 401 || status == 403) message = L(@"The API key is invalid or cannot access this model. Check Models.");
    else if (status == 404) message = L(@"API or model not found. Check the API URL and model ID.");
    else if (status == 400 || status == 422) message = L(@"The service rejected these parameters. Check the model ID or set reasoning to Service default.");
    else if (status == 429) message = L(@"The online service quota or rate limit was reached. Check your quota or try again later.");
    else if (status >= 300 && status < 400) message = L(@"The API URL redirected. Enter the final URL in Models.");
    return ModelProviderError(status, message);
}

@interface ModelProviderSessionDelegate : NSObject <NSURLSessionTaskDelegate>
@end
@implementation ModelProviderSessionDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    // Credentials and source text only go to the explicitly configured endpoint.
    completionHandler(nil);
}
@end
NSURLSession *ModelProviderSession(void) {
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        session = MakeModelProviderSession(NSURLSessionConfiguration.ephemeralSessionConfiguration);
    });
    return session;
}
NSURLSession *MakeModelProviderSession(NSURLSessionConfiguration *configuration) {
    configuration.URLCache = nil;
    configuration.HTTPCookieStorage = nil;
    configuration.URLCredentialStorage = nil;
    return [NSURLSession sessionWithConfiguration:configuration delegate:[ModelProviderSessionDelegate new] delegateQueue:nil];
}
NSURLSessionDataTask *RunTranslationRequestInSession(NSURLRequest *request, BOOL online, NSURLSession *session, TranslationCompletion completion) {
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        NSString *result = error ? nil : (online ? DecodeOnlineTranslation(data, status) : DecodeTranslation(data, status));
        completion(result, result ? nil : TranslationRequestError(status, online));
    }];
    [task resume];
    return task;
}
NSURLSessionDataTask *RunTranslationRequest(NSURLRequest *request, BOOL online, TranslationCompletion completion) {
    return RunTranslationRequestInSession(request, online, ModelProviderSession(), completion);
}
