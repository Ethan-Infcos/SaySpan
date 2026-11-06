#import "ModelProvider.h"

static int checks, failures;
static void CheckProvider(BOOL condition, NSString *message) {
    checks++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); }
}
static NSData *JSONData(id value) { return [NSJSONSerialization dataWithJSONObject:value options:0 error:NULL]; }
static NSDictionary *Body(NSURLRequest *request) { return request.HTTPBody ? [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL] : nil; }
static id Response(NSString *text, NSString *finish) { return @{@"choices":@[@{@"finish_reason":finish, @"message":@{@"content":text, @"reasoning_content":@"Not a translation"}}]}; }
static void PumpProvider(BOOL (^finished)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!finished() && deadline.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}

static NSInteger fixtureStatus;
static id fixtureResponse;
static NSURLRequest *observedRequest;
static BOOL delayResponse;
@interface ProviderFixtureProtocol : NSURLProtocol
@property(atomic) BOOL stopped;
@end
@implementation ProviderFixtureProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"provider-test.invalid"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    observedRequest = self.request;
    void (^respond)(void) = ^{
        if (self.stopped) return;
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:fixtureStatus HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:JSONData(fixtureResponse)];
        [self.client URLProtocolDidFinishLoading:self];
    };
    if (delayResponse) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC), dispatch_get_main_queue(), respond);
    else respond();
}
- (void)stopLoading { self.stopped = YES; }
@end

int RunModelProviderTests(void) {
    NSUserDefaults *preferences = NSUserDefaults.standardUserDefaults;
    NSDictionary *original = [preferences volatileDomainForName:NSArgumentDomain];
    NSMutableDictionary *arguments = [original mutableCopy];
    arguments[@"translationProvider"] = @"ollama";
    arguments[@"onlineReasoning"] = @"invalid";
    [preferences setVolatileDomain:arguments forName:NSArgumentDomain];
    NSString *keyFixture = [NSString stringWithFormat:@"https://keychain-test-%@.invalid/v1", NSUUID.UUID.UUIDString.lowercaseString];
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.protocolClasses = @[ProviderFixtureProtocol.class];
    NSURLSession *fixtureSession = MakeModelProviderSession(configuration);
    @try {
        CheckProvider(!UsesOnlineTranslation() && [ReadOnlineReasoning() isEqual:@"lowest"], @"Local mode is preserved and invalid reasoning falls back to lowest");
        CheckProvider([NormalizeOnlineBaseURL(@" HTTPS://API.OPENAI.COM/v1/chat/completions/ ", NULL) isEqual:@"https://api.openai.com/v1"], @"Chat endpoint input is normalized to a canonical API base");
        CheckProvider([NormalizeOnlineBaseURL(@"https://api.deepseek.com", NULL) isEqual:@"https://api.deepseek.com"], @"A provider without a v1 prefix retains its configured path");
        CheckProvider([NormalizeOnlineBaseURL(@"https://example.com/gateway/models", NULL) isEqual:@"https://example.com/gateway"], @"Custom gateway paths are preserved");
        for (NSString *bad in @[@"", @"http://example.com/v1", @"https://user:password@example.com", @"https://example.com?key=test", @"https://example.com#fragment", @"file:///tmp", @"https://exa mple.com", @"http://localhost.evil.test"])
            CheckProvider(!NormalizeOnlineBaseURL(bad, NULL), @"Invalid or credential-bearing API URLs are rejected");
        CheckProvider(NormalizeOnlineBaseURL(@"http://127.0.0.1:1234/v1", NULL) != nil, @"Explicit loopback-compatible services can use HTTP");
        CheckProvider([EffectiveOnlineReasoning(@"gpt-6.1-sol", @"lowest") isEqual:@"low"], @"Lowest uses low for a model that rejects none");
        CheckProvider([EffectiveOnlineReasoning(@"gpt-5-2025-08-07", @"lowest") isEqual:@"minimal"], @"Documented GPT-5 snapshots retain their minimum level");
        CheckProvider([EffectiveOnlineReasoning(@"gpt-5.2", @"lowest") isEqual:@"none"], @"Lowest disables reasoning where documented");
        CheckProvider([EffectiveOnlineReasoning(@"deepseek-flash", @"lowest") isEqual:@"none"], @"Lowest disables DeepSeek thinking instead of inheriting its high default");
        CheckProvider(!EffectiveOnlineReasoning(@"custom-model", @"lowest") && !EffectiveOnlineReasoning(@"gpt-4.1", @"default"), @"Unknown and ordinary models can omit reasoning parameters");
        CheckProvider([EffectiveOnlineReasoning(@"custom-model", @"high") isEqual:@"high"], @"Explicit reasoning choices reach compatible custom models");
        NSString *source = @"第一段\n\n  - 保留 API 和换行。";
        NSURLRequest *request = MakeOnlineTranslationRequest(source, @"auto", @"en", @"https://provider-test.invalid/v1", @"gpt-6.1-sol", @"fixture-only", @"lowest", NULL);
        NSDictionary *body = Body(request);
        CheckProvider([request.URL.absoluteString isEqual:@"https://provider-test.invalid/v1/chat/completions"] && [request.HTTPMethod isEqual:@"POST"], @"Online requests target the configured Chat Completions route");
        CheckProvider([[request valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer fixture-only"], @"The key is sent only as a bearer header");
        CheckProvider(![body.description containsString:@"fixture-only"] && !body[@"temperature"] && !body[@"options"], @"Keys and Ollama-specific sampling parameters never enter the online body");
        CheckProvider([body[@"messages"][1][@"content"] isEqual:source] && [body[@"messages"][0][@"content"] containsString:@"every explicit line break"], @"Online translations share language, formatting and custom-prompt rules");
        CheckProvider([body[@"reasoning_effort"] isEqual:@"low"] && ![body[@"stream"] boolValue], @"The lowest supported effort is serialized for non-streaming translation");
        CheckProvider(!Body(MakeOnlineTranslationRequest(source, @"auto", @"en", @"https://provider-test.invalid/v1", @"ordinary", @"fixture-only", @"default", NULL))[@"reasoning_effort"], @"Service-default mode omits unsupported reasoning fields");
        CheckProvider(!MakeOnlineTranslationRequest(source, @"auto", @"en", @"https://provider-test.invalid/v1", @"", @"fixture-only", @"low", NULL), @"Empty model IDs are rejected before networking");
        CheckProvider(!MakeOnlineModelsRequest(@"https://provider-test.invalid", @"bad\nkey", NULL), @"Credentials cannot inject HTTP headers");
        CheckProvider([MakeOnlineModelsRequest(@"https://provider-test.invalid/v1/", @"fixture-only", NULL).URL.path isEqual:@"/v1/models"], @"Model discovery uses the same configured prefix");
        CheckProvider([DecodeOnlineModels(JSONData(@{@"data":@[@{@"id":@"b"}, @{@"id":@"a"}, @{@"id":@"a"}, @{@"id":@42}, @{@"id":@"bad\nmodel"}]}), NULL) isEqual:@[@"a", @"b"]], @"Model discovery filters malformed entries and deduplicates IDs");
        CheckProvider(!DecodeOnlineModels(JSONData(@{@"models":@[]}), NULL), @"An incompatible model-list schema is reported without forcing a model switch");
        CheckProvider([DecodeOnlineTranslation(JSONData(Response(@"  Hello\n\n  - API\n", @"stop")), 200) isEqual:@"Hello\n\n  - API"], @"Only final content is decoded, preserving internal formatting");
        CheckProvider(!DecodeOnlineTranslation(JSONData(Response(@"Incomplete", @"length")), 200), @"Token-truncated translations are not presented as complete");
        CheckProvider(!DecodeOnlineTranslation(JSONData(@{@"choices":@[@{@"message":@{@"reasoning_content":@"reasoning only"}}]}), 200), @"Reasoning-only responses cannot be shown as translations");
        for (id invalid in @[@[], @{}, @{@"choices":@42}, @{@"choices":@[@"bad"]}, Response(@"", @"stop")])
            CheckProvider(!DecodeOnlineTranslation(JSONData(invalid), 200), @"Malformed online response shapes fail cleanly");
        CheckProvider([TranslationRequestError(401, YES).localizedDescription isEqual:L(@"The API key is invalid or cannot access this model. Check Models.")] && [TranslationRequestError(429, YES).localizedDescription isEqual:L(@"The online service quota or rate limit was reached. Check your quota or try again later.")], @"Authentication and quota failures produce actionable local messages");
        arguments[@"translationProvider"] = @"online";
        arguments[@"onlineBaseURL"] = @"not-a-url";
        [preferences setVolatileDomain:arguments forName:NSArgumentDomain];
        __block BOOL rejectedConfiguration = NO;
        NSURLSessionDataTask *invalidTask = TranslateTextWithLanguages(source, @"auto", @"en", ^(NSString *text, NSError *error) { rejectedConfiguration = !text && error != nil; });
        CheckProvider(!invalidTask && rejectedConfiguration, @"Invalid active online configuration fails before networking without falling back to Ollama");
        arguments[@"translationProvider"] = @"ollama";
        [preferences setVolatileDomain:arguments forName:NSArgumentDomain];

        fixtureStatus = 200; fixtureResponse = Response(@"Hello from the fixture.", @"stop");
        __block BOOL finished = NO;
        __block NSString *result;
        __block NSError *failure;
        RunTranslationRequestInSession(request, YES, fixtureSession, ^(NSString *text, NSError *error) { result = text; failure = error; finished = YES; });
        PumpProvider(^BOOL{ return finished; });
        CheckProvider(finished && !failure && [result isEqual:@"Hello from the fixture."], @"The production HTTP session completes an online translation through a local protocol fixture");
        CheckProvider([[observedRequest valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer fixture-only"], @"Transport preserves authorization to the configured destination");
        finished = NO; fixtureStatus = 401; fixtureResponse = @{@"error":@{@"message":@"Do not expose this remote error or fixture-only"}};
        RunTranslationRequestInSession(request, YES, fixtureSession, ^(NSString *text, NSError *error) { result = text; failure = error; finished = YES; });
        PumpProvider(^BOOL{ return finished; });
        CheckProvider(finished && !result && failure.code == 401 && ![failure.localizedDescription containsString:@"fixture-only"], @"Remote error bodies and credentials never leak through displayed errors");
        finished = NO; fixtureStatus = 200; fixtureResponse = Response(@"Too late", @"stop"); delayResponse = YES;
        NSURLSessionDataTask *task = RunTranslationRequestInSession(request, YES, fixtureSession, ^(NSString *text, NSError *error) { result = text; failure = error; finished = YES; });
        [task cancel]; PumpProvider(^BOOL{ return finished; });
        CheckProvider(finished && !result && failure, @"Cancelling an online translation prevents a successful late result");
        delayResponse = NO;
        __block NSURLRequest *redirect = request;
        id<NSURLSessionTaskDelegate> delegate = (id)ModelProviderSession().delegate;
        [delegate URLSession:ModelProviderSession() task:task willPerformHTTPRedirection:[[NSHTTPURLResponse alloc] initWithURL:request.URL statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:nil] newRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://another-provider.invalid"]] completionHandler:^(NSURLRequest *next) { redirect = next; }];
        CheckProvider(!redirect, @"The production redirect delegate refuses to forward credentials or source text");

        NSError *keyError;
        CheckProvider(SaveOnlineAPIKey(keyFixture, @"fixture-only", &keyError), @"The application can store its own generated test credential in Keychain");
        CheckProvider(HasOnlineAPIKey(keyFixture) && [ReadOnlineAPIKey(keyFixture, NO, NULL) isEqual:@"fixture-only"], @"The stored credential can be read without a background authorization prompt");
        CheckProvider(!HasOnlineAPIKey([keyFixture stringByAppendingString:@"/other"]), @"Credentials are scoped to the exact normalized API base");
        CheckProvider(SaveOnlineAPIKey(keyFixture, @"fixture-replaced", NULL) && [ReadOnlineAPIKey(keyFixture, NO, NULL) isEqual:@"fixture-replaced"], @"Replacing an API key updates its existing endpoint record");
        CheckProvider(DeleteOnlineAPIKey(keyFixture, NULL) && !HasOnlineAPIKey(keyFixture), @"The generated test credential is removed after verification");
        printf("%d provider checks, %d failures\n", checks, failures);
        return failures ? 1 : 0;
    } @finally {
        DeleteOnlineAPIKey(keyFixture, NULL);
        [fixtureSession invalidateAndCancel];
        [preferences setVolatileDomain:original forName:NSArgumentDomain];
    }
}
