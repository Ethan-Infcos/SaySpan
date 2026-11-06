#import "SelectionTranslation.h"

void TraceSelectionEvent(NSString *event, NSDictionary *details) {
    static BOOL enabled;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ enabled = [NSProcessInfo.processInfo.arguments containsObject:@"--trace-selection"]; });
    if (!enabled) return;
    NSMutableDictionary *entry = [details mutableCopy] ?: [NSMutableDictionary dictionary];
    entry[@"event"] = event;
    entry[@"uptime"] = @(NSProcessInfo.processInfo.systemUptime);
    NSData *data = [NSJSONSerialization dataWithJSONObject:entry options:NSJSONWritingSortedKeys error:NULL];
    if (data) fprintf(stderr, "SELECTION %s\n", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}

NSNotificationName const SelectionTranslationCompositionDidChangeNotification = @"SelectionTranslationCompositionDidChange";
static NSHashTable *compositionOwners;
static BOOL compositionWasActive;
BOOL SelectionTranslationCompositionActive(void) {
    for (id<SelectionTranslationCompositionOwner> owner in compositionOwners.allObjects)
        if (owner.selectionTranslationCompositionActive) return YES;
    return NO;
}
void RefreshSelectionTranslationCompositionActivity(void) {
    BOOL isActive = SelectionTranslationCompositionActive();
    if (compositionWasActive == isActive) return;
    compositionWasActive = isActive;
    [NSNotificationCenter.defaultCenter postNotificationName:SelectionTranslationCompositionDidChangeNotification object:nil];
}
void SetSelectionTranslationCompositionActive(id<SelectionTranslationCompositionOwner> owner, BOOL active) {
    if (!owner) return;
    if (!compositionOwners) compositionOwners = [NSHashTable hashTableWithOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality];
    if (active) [compositionOwners addObject:owner];
    else [compositionOwners removeObject:owner];
    RefreshSelectionTranslationCompositionActivity();
}

BOOL ReadSelectionTranslationEnabled(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:@"selectionTranslationEnabled"];
    return value ? [value boolValue] : YES;
}
BOOL ReadSelectionTranslationAutomatic(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:@"selectionTranslationAutomatic"];
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}
NSString *ReadSelectionTranslationTarget(void) {
    // Both translation entry points now use the language pair, including existing installations.
    return @"auto";
}

NSRect SelectionRectFromAccessibility(CGRect rect, CGFloat primaryScreenTop) {
    return NSMakeRect(rect.origin.x, primaryScreenTop - CGRectGetMaxY(rect), rect.size.width, rect.size.height);
}
NSRect SelectionPanelFrame(NSRect anchor, NSSize size, NSRect visibleFrame) {
    size.width = MIN(size.width, visibleFrame.size.width - 12);
    size.height = MIN(size.height, visibleFrame.size.height - 12);
    CGFloat x = MIN(NSMaxX(anchor) + 6, NSMaxX(visibleFrame) - size.width - 6);
    x = MAX(NSMinX(visibleFrame) + 6, x);
    CGFloat y = NSMinY(anchor) - size.height - 6;
    if (y < NSMinY(visibleFrame) + 6) y = NSMaxY(anchor) + 6;
    y = MAX(NSMinY(visibleFrame) + 6, MIN(y, NSMaxY(visibleFrame) - size.height - 6));
    return NSMakeRect(x, y, size.width, size.height);
}

@implementation TextSelection
- (id)copyWithZone:(NSZone *)zone {
    TextSelection *copy = [[TextSelection allocWithZone:zone] init];
    copy.text = _text;
    copy.identifier = _identifier;
    copy.processID = _processID;
    copy.anchor = _anchor;
    copy.tooLong = _tooLong;
    return copy;
}
- (BOOL)matches:(TextSelection *)other {
    return other && _processID == other.processID && [_identifier isEqual:other.identifier] && [_text isEqual:other.text] && _tooLong == other.tooLong;
}
@end

@implementation SelectionTranslation {
    NSUInteger _revision;
    NSURLSessionDataTask *_request;
    TextSelection *_dismissed;
}
- (void)dealloc { [_request cancel]; }
- (void)notify { if (_changed) _changed(); }
- (void)invalidate {
    ++_revision;
    [_request cancel];
    _request = nil;
    _loading = NO;
    _result = @"";
    _status = @"";
    _target = @"";
    _sourceLanguage = @"auto";
}
- (void)observeSelection:(TextSelection *)selection {
    if (_suspended) return;
    if (!selection.tooLong && ![selection.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) selection = nil;
    // Keep the first anchor, including mouse-position fallbacks, for this selection.
    if ([_selection matches:selection]) return;
    TraceSelectionEvent(@"selection-change", @{@"present":@(selection != nil), @"length":@(selection.text.length), @"identifierChanged":@(_selection && ![_selection.identifier isEqual:selection.identifier])});
    [self invalidate];
    _selection = [selection copy];
    if (!selection) _dismissed = nil;
    _stage = selection && ![_dismissed matches:selection] ? SelectionTranslationBadge : SelectionTranslationHidden;
    if (_automaticallyTranslates && _stage == SelectionTranslationBadge) [self scheduleAutomaticTranslation];
    [self notify];
}
- (void)setSuspended:(BOOL)suspended {
    if (_suspended == suspended) return;
    _suspended = suspended;
    [self invalidate];
    _selection = nil;
    _dismissed = nil;
    _stage = SelectionTranslationHidden;
    [self notify];
}
- (void)setAutomaticallyTranslates:(BOOL)automaticallyTranslates {
    if (_automaticallyTranslates == automaticallyTranslates) return;
    _automaticallyTranslates = automaticallyTranslates;
    if (automaticallyTranslates && _stage == SelectionTranslationBadge) {
        [self scheduleAutomaticTranslation];
    } else if (!automaticallyTranslates && _stage == SelectionTranslationPending) {
        ++_revision;
        _stage = SelectionTranslationBadge;
    }
    [self notify];
}
- (void)scheduleAutomaticTranslation {
    _stage = SelectionTranslationPending;
    NSUInteger revision = ++_revision;
    __weak SelectionTranslation *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        SelectionTranslation *self = weakSelf;
        if (!self || self->_suspended || !self->_automaticallyTranslates || self->_revision != revision || self->_stage != SelectionTranslationPending) return;
        [self translateWithPreference:ReadSelectionTranslationTarget()];
    });
}
- (void)translateWithPreference:(NSString *)preference {
    if (_suspended || !_selection || _stage == SelectionTranslationHidden) return;
    TraceSelectionEvent(@"translate-start", @{@"length":@(_selection.text.length)});
    [self invalidate];
    _stage = SelectionTranslationResult;
    if (_selection.tooLong || _selection.text.length > MaximumSelectionLength) {
        _status = L(@"The selection is too long. Select fewer characters and try again (maximum 6000).");
        [self notify];
        return;
    }
    _target = TranslationTargetForText(_selection.text, preference);
    _sourceLanguage = @"auto";
    _loading = YES;
    _status = L(@"Translating…");
    [self notify];
    NSUInteger revision = _revision;
    __weak SelectionTranslation *weakSelf = self;
    TranslationCompletion completion = ^(NSString *translated, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SelectionTranslation *self = weakSelf;
            if (!self || self->_revision != revision || self->_stage != SelectionTranslationResult) return;
            self->_loading = NO;
            NSString *clean = TranslationWithSourceLayout(translated, self->_selection.text);
            self->_result = !error && clean.length ? clean : @"";
            NSString *message = [error.domain isEqual:@"DualLineIME.Provider"] ? error.localizedDescription : L(@"Translation failed. Check the selected model.");
            self->_status = self->_result.length ? @"" : [message stringByAppendingString:L(@" Select the text again to retry.")];
            TraceSelectionEvent(@"translate-finish", @{@"success":@(self->_result.length > 0)});
            [self notify];
        });
    };
    _request = _service ? _service(_selection.text, _target, completion) : TranslateTextWithLanguages(_selection.text, _sourceLanguage, _target, completion);
}
- (void)dismiss {
    TraceSelectionEvent(@"dismiss", @{@"stage":@(_stage)});
    _dismissed = _selection;
    [self invalidate];
    _stage = SelectionTranslationHidden;
    [self notify];
}
@end
