#import "SelectionTranslation.h"
#import <ApplicationServices/ApplicationServices.h>

void PrepareSelectionWebAccessibility(AXUIElementRef app, pid_t pid);

BOOL SelectionTranslationHasPermission(void) { return AXIsProcessTrusted(); }
void RequestSelectionTranslationPermission(void) {
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}

static id Attribute(AXUIElementRef element, CFStringRef name) {
    CFTypeRef result = NULL;
    if (!element) return nil;
    AXError error = AXUIElementCopyAttributeValue(element, name, &result);
    if (error != kAXErrorSuccess) {
        if (error != kAXErrorAttributeUnsupported && error != kAXErrorNoValue)
            TraceSelectionEvent(@"ax-error", @{@"attribute":(__bridge NSString *)name, @"code":@(error)});
        return nil;
    }
    return CFBridgingRelease(result);
}
static id Parameter(AXUIElementRef element, CFStringRef name, CFTypeRef parameter) {
    CFTypeRef result = NULL;
    if (!parameter || AXUIElementCopyParameterizedAttributeValue(element, name, parameter, &result) != kAXErrorSuccess) return nil;
    return CFBridgingRelease(result);
}
static BOOL IsElement(id value) { return value && CFGetTypeID((__bridge CFTypeRef)value) == AXUIElementGetTypeID(); }
static BOOL IsSecure(AXUIElementRef element) {
    return [Attribute(element, kAXSubroleAttribute) isEqual:(__bridge NSString *)kAXSecureTextFieldSubrole];
}
static BOOL RectValue(id value, CGRect *rect) {
    return value && CFGetTypeID((__bridge CFTypeRef)value) == AXValueGetTypeID() &&
        AXValueGetType((__bridge AXValueRef)value) == kAXValueCGRectType && AXValueGetValue((__bridge AXValueRef)value, kAXValueCGRectType, rect);
}

static TextSelection *SelectionFromElement(AXUIElementRef element, pid_t pid, NSPoint fallback, CGFloat top, CFAbsoluteTime deadline) {
    if (CFAbsoluteTimeGetCurrent() > deadline || IsSecure(element)) return nil;
    id rangeValue = Attribute(element, kAXSelectedTextRangeAttribute);
    CFRange range = CFRangeMake(-1, 0);
    BOOL hasRange = rangeValue && CFGetTypeID((__bridge CFTypeRef)rangeValue) == AXValueGetTypeID() &&
        AXValueGetType((__bridge AXValueRef)rangeValue) == kAXValueCFRangeType &&
        AXValueGetValue((__bridge AXValueRef)rangeValue, kAXValueCFRangeType, &range);
    if (hasRange && (range.location < 0 || range.length <= 0)) return nil;
    BOOL tooLong = hasRange && range.length > MaximumSelectionLength;
    id text = tooLong ? @"" : Attribute(element, kAXSelectedTextAttribute);
    id marker = nil;
    if (!tooLong && (![text isKindOfClass:NSString.class] || ![text length]) && hasRange)
        text = Parameter(element, kAXStringForRangeParameterizedAttribute, (__bridge CFTypeRef)rangeValue);
    if (!tooLong && (![text isKindOfClass:NSString.class] || ![text length])) {
        // WebKit and Chromium may expose document selection through text markers.
        marker = Attribute(element, CFSTR("AXSelectedTextMarkerRange"));
        text = Parameter(element, CFSTR("AXStringForTextMarkerRange"), (__bridge CFTypeRef)marker);
    }
    if (!tooLong && (![text isKindOfClass:NSString.class] || ![text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length)) return nil;
    tooLong = tooLong || [text length] > MaximumSelectionLength;
    TextSelection *selection = [TextSelection new];
    selection.text = tooLong ? @"" : text;
    selection.tooLong = tooLong;
    selection.processID = pid;
    selection.identifier = [NSString stringWithFormat:@"%d:%lu:%ld:%ld", pid, (unsigned long)CFHash(element), (long)range.location, (long)range.length];
    selection.anchor = NSMakeRect(fallback.x, fallback.y, 0, 0);
    CGRect rect = CGRectZero;
    id bounds;
    if (hasRange && !tooLong && range.location <= LONG_MAX - range.length) {
        CFRange end = CFRangeMake(range.location + range.length - 1, 1);
        AXValueRef endValue = AXValueCreate(kAXValueCFRangeType, &end);
        bounds = Parameter(element, kAXBoundsForRangeParameterizedAttribute, endValue);
        CFRelease(endValue);
        if (!RectValue(bounds, &rect)) bounds = Parameter(element, kAXBoundsForRangeParameterizedAttribute, (__bridge CFTypeRef)rangeValue);
    }
    if (!RectValue(bounds, &rect) && marker)
        bounds = Parameter(element, CFSTR("AXBoundsForTextMarkerRange"), (__bridge CFTypeRef)marker);
    if (RectValue(bounds, &rect) && isfinite(rect.origin.x) && isfinite(rect.origin.y) && isfinite(rect.size.width) && isfinite(rect.size.height) && rect.size.height > 0)
        selection.anchor = SelectionRectFromAccessibility(rect, top);
    return selection;
}

// Called only on the reader's serial background queue. No clipboard or keystrokes.
TextSelection *ReadTextSelection(pid_t pid, NSPoint point, CGFloat primaryTop) {
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    AXUIElementSetMessagingTimeout(app, 0.08);
    PrepareSelectionWebAccessibility(app, pid);
    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime deadline = started + 0.45;
    id focused = Attribute(app, kAXFocusedUIElementAttribute);
    if (IsElement(focused) && IsSecure((__bridge AXUIElementRef)focused)) { CFRelease(app); return nil; }
    NSMutableArray *roots = [NSMutableArray array];
    if (IsElement(focused)) [roots addObject:focused];
    AXUIElementRef hit = NULL;
    if (AXUIElementCopyElementAtPosition(app, point.x, primaryTop - point.y, &hit) == kAXErrorSuccess && hit)
        [roots addObject:CFBridgingRelease(hit)];
    NSMutableSet *visited = [NSMutableSet set];
    TextSelection *selection = nil;
    for (id root in roots) {
        id element = root;
        for (NSUInteger depth = 0; IsElement(element) && depth < 7 && CFAbsoluteTimeGetCurrent() < deadline; depth++) {
            if ([visited containsObject:element]) break;
            [visited addObject:element];
            selection = SelectionFromElement((__bridge AXUIElementRef)element, pid, point, primaryTop, deadline);
            if (selection) break;
            element = Attribute((__bridge AXUIElementRef)element, kAXParentAttribute);
        }
        if (selection) break;
    }
    if (!selection && CFAbsoluteTimeGetCurrent() < deadline) {
        id window = Attribute(app, kAXFocusedWindowAttribute);
        NSMutableArray *queue = [NSMutableArray array];
        if (IsElement(window)) [queue addObject:window];
        // A bounded fallback handles read-only document areas that are not focused.
        for (NSUInteger index = 0; index < queue.count && index < 64 && CFAbsoluteTimeGetCurrent() < deadline; index++) {
            id element = queue[index];
            if (![visited containsObject:element]) {
                [visited addObject:element];
                selection = SelectionFromElement((__bridge AXUIElementRef)element, pid, point, primaryTop, deadline);
                if (selection) break;
            }
            CFArrayRef children = NULL;
            if (AXUIElementCopyAttributeValues((__bridge AXUIElementRef)element, kAXChildrenAttribute, 0, 12, &children) == kAXErrorSuccess && children) {
                for (id child in CFBridgingRelease(children)) {
                    if (IsElement(child) && queue.count < 96) [queue addObject:child];
                }
            }
        }
    }
    CFRelease(app);
    TraceSelectionEvent(@"reader", @{@"pid":@(pid), @"focused":@(IsElement(focused)), @"visited":@(visited.count), @"found":@(selection != nil), @"milliseconds":@((CFAbsoluteTimeGetCurrent() - started) * 1000)});
    return selection;
}
