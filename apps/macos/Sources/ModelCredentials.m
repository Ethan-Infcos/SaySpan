#import "ModelProvider.h"
#import <Security/Security.h>
#import <LocalAuthentication/LocalAuthentication.h>

static NSMutableDictionary *KeyQuery(NSString *baseURL) {
    NSString *canonical = NormalizeOnlineBaseURL(baseURL, NULL);
    if (!canonical) return nil;
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService:@"local.inputmethod.DualLineIME.online-api",
              (__bridge id)kSecAttrAccount:canonical} mutableCopy];
}
static NSError *KeyError(OSStatus status) {
    return ModelProviderError(status, L(@"Could not access the API key in Keychain. Re-enter it in Models or complete system authorization."));
}
BOOL HasOnlineAPIKey(NSString *baseURL) {
    NSMutableDictionary *query = KeyQuery(baseURL);
    if (!query) return NO;
    query[(__bridge id)kSecReturnAttributes] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    LAContext *context = [LAContext new];
    context.interactionNotAllowed = YES;
    query[(__bridge id)kSecUseAuthenticationContext] = context;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL);
    return status == errSecSuccess || status == errSecInteractionNotAllowed || status == errSecAuthFailed;
}
NSString *ReadOnlineAPIKey(NSString *baseURL, BOOL allowInteraction, NSError **error) {
    NSMutableDictionary *query = KeyQuery(baseURL);
    if (!query) return nil;
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    LAContext *context = [LAContext new];
    context.interactionNotAllowed = !allowInteraction;
    query[(__bridge id)kSecUseAuthenticationContext] = context;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    NSData *data = CFBridgingRelease(result);
    if (status != errSecSuccess) { if (error) *error = KeyError(status); return nil; }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
BOOL SaveOnlineAPIKey(NSString *baseURL, NSString *key, NSError **error) {
    NSMutableDictionary *query = KeyQuery(baseURL);
    if (!query || !key.length) { if (error) *error = ModelProviderError(2, L(@"Enter an API URL and API key.")); return NO; }
    NSDictionary *update = @{(__bridge id)kSecValueData:[key dataUsingEncoding:NSUTF8StringEncoding]};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
    if (status == errSecItemNotFound) {
        [query addEntriesFromDictionary:update];
        query[(__bridge id)kSecAttrLabel] = L(@"{appName} · Online model API key");
        status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    }
    if (status != errSecSuccess && error) *error = KeyError(status);
    return status == errSecSuccess;
}
BOOL DeleteOnlineAPIKey(NSString *baseURL, NSError **error) {
    NSMutableDictionary *query = KeyQuery(baseURL);
    if (!query) return YES;
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    if (status != errSecSuccess && status != errSecItemNotFound && error) *error = KeyError(status);
    return status == errSecSuccess || status == errSecItemNotFound;
}
