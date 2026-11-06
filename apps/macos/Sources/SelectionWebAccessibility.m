#import "SelectionTranslation.h"
#import <ApplicationServices/ApplicationServices.h>

BOOL SelectionApplicationUsesChromium(NSURL *bundleURL) {
    if (!bundleURL.isFileURL) return NO;
    NSURL *frameworks = [bundleURL URLByAppendingPathComponent:@"Contents/Frameworks" isDirectory:YES];
    NSArray<NSURL *> *children = [NSFileManager.defaultManager contentsOfDirectoryAtURL:frameworks includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:NULL];
    for (NSURL *framework in children) {
        if (![framework.pathExtension isEqual:@"framework"]) continue;
        // Chromium distributions can rename their framework; the ICU resource is shared.
        NSURL *data = [framework URLByAppendingPathComponent:@"Resources/icudtl.dat"];
        if ([NSFileManager.defaultManager fileExistsAtPath:data.path]) return YES;
    }
    return NO;
}

BOOL EnableSelectionWebAccessibility(BOOL chromium, NSNumber *(^read)(NSString *), BOOL (^enable)(NSString *)) {
    if (!chromium) return NO;
    // Electron documents AXManualAccessibility. Chromium also accepts the AT request
    // AXEnhancedUserInterface; newer Chromium builds can reject the former attribute.
    for (NSString *attribute in @[@"AXManualAccessibility", @"AXEnhancedUserInterface"]) {
        if ([read(attribute) boolValue]) return YES;
        if (enable(attribute) && [read(attribute) boolValue]) return YES;
    }
    return NO;
}

// Called on the selection reader's serial queue, only after its permission check.
void PrepareSelectionWebAccessibility(AXUIElementRef app, pid_t pid) {
    static NSMutableDictionary<NSString *, NSNumber *> *attempts;
    if (!attempts) attempts = [NSMutableDictionary dictionary];
    NSRunningApplication *running = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (!running.bundleURL || running.terminated) return;
    NSString *instance = [NSString stringWithFormat:@"%d:%.6f:%@", pid, running.launchDate.timeIntervalSinceReferenceDate, running.bundleURL.path];
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (attempts[instance] && attempts[instance].doubleValue > now) return;
    if (attempts.count >= 64) [attempts removeAllObjects];
    if (!SelectionApplicationUsesChromium(running.bundleURL)) { attempts[instance] = @(DBL_MAX); return; }
    BOOL enabled = EnableSelectionWebAccessibility(YES, ^NSNumber *(NSString *attribute) {
        CFTypeRef result = NULL;
        AXError error = AXUIElementCopyAttributeValue(app, (__bridge CFStringRef)attribute, &result);
        id value = CFBridgingRelease(result);
        return error == kAXErrorSuccess && [value isKindOfClass:NSNumber.class] ? value : nil;
    }, ^BOOL(NSString *attribute) {
        AXError error = AXUIElementSetAttributeValue(app, (__bridge CFStringRef)attribute, kCFBooleanTrue);
        TraceSelectionEvent(@"web-accessibility-enable", @{@"pid":@(pid), @"attribute":attribute, @"error":@(error)});
        return error == kAXErrorSuccess;
    });
    // Repeating the request on every poll restarts Chromium's two-second debounce.
    // Keep successful requests for this process lifetime; retry transient failures slowly.
    attempts[instance] = enabled ? @(DBL_MAX) : @(now + 10);
    TraceSelectionEvent(@"web-accessibility-ready", @{@"pid":@(pid), @"enabled":@(enabled)});
}
