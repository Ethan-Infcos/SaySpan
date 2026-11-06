#import "SelectionTranslation.h"

TextSelection *ReadTextSelection(pid_t pid, NSPoint point, CGFloat primaryTop);

@interface SelectionPanel : NSPanel
@property(nonatomic) BOOL allowsKey;
@property(nonatomic, copy) void (^dismiss)(void);
@end
@implementation SelectionPanel
- (BOOL)canBecomeKey { return _allowsKey; }
- (BOOL)canBecomeMain { return NO; }
- (void)cancelOperation:(id)sender { if (_dismiss) _dismiss(); }
@end

@interface SelectionOverlay : NSObject <NSTextViewDelegate>
- (void)start;
- (void)showPreview;
@end

@implementation SelectionOverlay {
    SelectionTranslation *_model;
    SelectionPanel *_badge;
    SelectionPanel *_card;
    NSTextField *_title;
    NSTextField *_source;
    NSTextView *_translation;
    NSButton *_copy;
    NSButton *_automatic;
    NSUInteger _copyFeedbackRevision;
    NSTimer *_timer;
    id _globalMonitor;
    id _localMonitor;
    id _activationObserver;
    id _compositionObserver;
    NSTimeInterval _resumeSelectionAfter;
    NSString *_lastScanReason;
    dispatch_queue_t _readerQueue;
    BOOL _reading;
    BOOL _translateRequested;
    NSUInteger _scanRevision;
    NSPoint _mouseDownPoint;
    NSInteger _mouseClickCount;
    NSWindow *_preview;
    NSTextView *_previewText;
    BOOL _previewCardAttached;
    NSString *_interfaceLanguage;
}
- (instancetype)init {
    if ((self = [super init])) {
        _model = [SelectionTranslation new];
        _model.automaticallyTranslates = ReadSelectionTranslationAutomatic();
        __weak SelectionOverlay *weakSelf = self;
        _model.changed = ^{ [weakSelf render]; };
        _readerQueue = dispatch_queue_create("local.dualline.selection-reader", DISPATCH_QUEUE_SERIAL);
        [self createPanels];
    }
    return self;
}
- (SelectionPanel *)panelWithSize:(NSSize)size {
    SelectionPanel *panel = [[SelectionPanel alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height) styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    panel.releasedWhenClosed = NO;
    panel.hidesOnDeactivate = NO;
    panel.becomesKeyOnlyIfNeeded = YES;
    panel.opaque = NO;
    panel.backgroundColor = NSColor.clearColor;
    panel.hasShadow = YES;
    panel.level = NSPopUpMenuWindowLevel;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    NSVisualEffectView *background = [[NSVisualEffectView alloc] initWithFrame:panel.contentView.bounds];
    background.material = NSVisualEffectMaterialPopover;
    background.state = NSVisualEffectStateActive;
    background.wantsLayer = YES;
    background.layer.cornerRadius = 10;
    panel.contentView = background;
    return panel;
}
- (void)createPanels {
    _interfaceLanguage = CurrentInterfaceLanguage();
    _badge = [self panelWithSize:NSMakeSize(32, 32)];
    _badge.title = L(@"Selection");
    NSButton *translate = [NSButton buttonWithTitle:L(@"Tr") target:self action:@selector(translate:)];
    translate.font = [NSFont systemFontOfSize:18 weight:NSFontWeightSemibold];
    translate.bordered = NO;
    translate.contentTintColor = NSColor.controlAccentColor;
    translate.toolTip = L(@"Translate selected text");
    translate.accessibilityLabel = L(@"Translate selected text");
    translate.frame = _badge.contentView.bounds;
    translate.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_badge.contentView addSubview:translate];

    _card = [self panelWithSize:NSMakeSize(420, 270)];
    _card.title = L(@"Selected text translation");
    _card.allowsKey = YES;
    __weak SelectionOverlay *weakSelf = self;
    _card.dismiss = ^{ [weakSelf close:nil]; };
    _title = [NSTextField labelWithString:L(@"Selection")];
    _title.font = [NSFont boldSystemFontOfSize:15];
    _source = [NSTextField wrappingLabelWithString:@""];
    _source.font = [NSFont systemFontOfSize:12];
    _source.textColor = NSColor.secondaryLabelColor;
    _source.maximumNumberOfLines = 3;
    NSScrollView *scroll = [NSScrollView new];
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.drawsBackground = NO;
    _translation = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 388, 150)];
    _translation.editable = NO;
    _translation.selectable = YES;
    _translation.richText = NO;
    _translation.drawsBackground = NO;
    _translation.font = [NSFont systemFontOfSize:15];
    _translation.textColor = NSColor.labelColor;
    _translation.textContainerInset = NSMakeSize(2, 4);
    _translation.verticallyResizable = YES;
    _translation.horizontallyResizable = NO;
    _translation.autoresizingMask = NSViewWidthSizable;
    _translation.textContainer.widthTracksTextView = YES;
    scroll.documentView = _translation;
    _copy = [NSButton buttonWithTitle:@"" target:self action:@selector(copyResult:)];
    _copy.bordered = NO;
    _copy.controlSize = NSControlSizeSmall;
    _copy.imagePosition = NSImageOnly;
    [self showCopyFeedback:NO];
    _automatic = [NSButton checkboxWithTitle:L(@"Auto-translate") target:self action:@selector(toggleAutomaticTranslation:)];
    _automatic.controlSize = NSControlSizeSmall;
    _automatic.font = [NSFont systemFontOfSize:11];
    _automatic.toolTip = L(@"Show translations automatically when text is selected. Turn off to use the Translate button. The current result stays visible.");
    _automatic.accessibilityLabel = L(@"Automatically translate selected text");
    NSStackView *header = [NSStackView stackViewWithViews:@[_title, [NSView new], _automatic, _copy]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.distribution = NSStackViewDistributionFill;
    header.spacing = 8;
    NSStackView *stack = [NSStackView stackViewWithViews:@[header, _source, scroll]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_card.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:_card.contentView.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:_card.contentView.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:_card.contentView.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:_card.contentView.bottomAnchor constant:-14],
        [header.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [_copy.widthAnchor constraintEqualToConstant:24],
        [_copy.heightAnchor constraintEqualToConstant:24],
        [_source.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:120]
    ]];
}
- (NSScreen *)screenForAnchor:(NSRect)anchor {
    for (NSScreen *screen in NSScreen.screens)
        if (NSIntersectsRect(screen.frame, NSInsetRect(anchor, -1, -1))) return screen;
    return NSScreen.mainScreen;
}
- (void)render {
    if (![_interfaceLanguage isEqual:CurrentInterfaceLanguage()] && !_previewCardAttached) {
        [_badge orderOut:nil];
        [_card orderOut:nil];
        [self createPanels];
    }
    TraceSelectionEvent(@"render", @{@"stage":@(_model.stage), @"suspended":@(_model.suspended), @"loading":@(_model.loading)});
    ++_copyFeedbackRevision;
    _automatic.state = ReadSelectionTranslationAutomatic() ? NSControlStateValueOn : NSControlStateValueOff;
    if (_model.stage == SelectionTranslationHidden || _model.stage == SelectionTranslationPending) {
        _translation.string = @"";
        _source.stringValue = @"";
        if (_previewCardAttached) [_preview orderOut:nil];
        [_badge orderOut:nil]; [_card orderOut:nil]; return;
    }
    NSRect anchor = _model.selection.anchor;
    NSRect visible = [self screenForAnchor:anchor].visibleFrame;
    if (_model.stage == SelectionTranslationBadge) {
        [_card orderOut:nil];
        [_badge setFrame:SelectionPanelFrame(anchor, NSMakeSize(32, 32), visible) display:YES];
        [_badge orderFrontRegardless];
        return;
    }
    [_badge orderOut:nil];
    _title.stringValue = _model.target.length ? [L(@"Translation · ") stringByAppendingString:TranslationLanguageName(_model.target)] : L(@"Selection");
    NSString *original = _model.selection.text ?: @"";
    if (original.length > 160) original = [[original substringWithRange:[original rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, 160)]] stringByAppendingString:@"…"];
    _source.stringValue = original.length ? [L(@"Source: ") stringByAppendingString:original] : L(@"The selection exceeds the character limit");
    NSString *display = _model.result.length ? _model.result : _model.status;
    if (![_translation.string isEqual:display]) _translation.string = display ?: @"";
    _translation.textColor = _model.result.length ? NSColor.labelColor : NSColor.secondaryLabelColor;
    _copy.enabled = _model.result.length > 0;
    [self showCopyFeedback:NO];
    CGFloat headerWidth = _title.intrinsicContentSize.width + _automatic.intrinsicContentSize.width + 88;
    NSRect frame = SelectionPanelFrame(anchor, NSMakeSize(MIN(visible.size.width, MAX(420, headerWidth)), 270), visible);
    [_card setFrame:frame display:YES];
    [_card orderFrontRegardless];
    TraceSelectionEvent(@"card-shown", @{@"visible":@(_card.visible), @"key":@(_card.keyWindow), @"frame":NSStringFromRect(_card.frame)});
    if (_preview && [NSProcessInfo.processInfo.arguments containsObject:@"--selection-result-preview"]) {
        // Window-based UI inspectors cannot capture nonactivating panels.
        // Reuse the card's actual content in a standard window for layout checks.
        [_card orderOut:nil];
        if (!_previewCardAttached) {
            _previewCardAttached = YES;
            _preview.contentView = _card.contentView;
            [_preview setContentSize:NSMakeSize(420, 270)];
            _preview.title = L(@"{appName} Translation Preview");
        }
        [_preview makeKeyAndOrderFront:nil];
    }
}
- (BOOL)pointerInPanels {
    NSPoint point = NSEvent.mouseLocation;
    return (_badge.visible && NSPointInRect(point, _badge.frame)) || (_card.visible && NSPointInRect(point, _card.frame));
}
- (void)close:(id)sender {
    ++_scanRevision;
    _translateRequested = NO;
    [_model dismiss];
}
- (void)copyResult:(id)sender {
    if (!_model.result.length) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:_model.result forType:NSPasteboardTypeString];
    [self showCopyFeedback:YES];
    NSUInteger revision = ++_copyFeedbackRevision;
    __weak SelectionOverlay *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        SelectionOverlay *self = weakSelf;
        if (self && self->_copyFeedbackRevision == revision) [self showCopyFeedback:NO];
    });
}
- (void)showCopyFeedback:(BOOL)copied {
    NSString *label = copied ? L(@"Copied") : L(@"Copy translation");
    NSImage *image = [NSImage imageWithSystemSymbolName:copied ? @"checkmark" : @"doc.on.doc" accessibilityDescription:label];
    _copy.image = [image imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightRegular]];
    _copy.contentTintColor = copied ? NSColor.controlAccentColor : NSColor.secondaryLabelColor;
    _copy.toolTip = label;
    _copy.accessibilityLabel = label;
}
- (void)toggleAutomaticTranslation:(NSButton *)sender {
    BOOL automatic = sender.state == NSControlStateValueOn;
    [[NSUserDefaults standardUserDefaults] setBool:automatic forKey:@"selectionTranslationAutomatic"];
    _model.automaticallyTranslates = automatic;
}
- (void)translate:(id)sender {
    if (_preview || _model.stage == SelectionTranslationResult) {
        [_model translateWithPreference:ReadSelectionTranslationTarget()];
    } else {
        // Refresh selection at click time so a stale badge cannot translate old text.
        [self scanWithTranslation:YES];
    }
}
- (void)traceScan:(NSString *)reason {
    if ([_lastScanReason isEqual:reason]) return;
    _lastScanReason = reason;
    TraceSelectionEvent(@"scan", @{@"reason":reason, @"stage":@(_model.stage), @"suspended":@(_model.suspended)});
}
- (void)scanWithTranslation:(BOOL)translate {
    // Weak owners or palettes can disappear without an IMK commit/deactivate callback.
    RefreshSelectionTranslationCompositionActivity();
    if (_model.suspended) { [self traceScan:@"composition"]; return; }
    if (NSDate.timeIntervalSinceReferenceDate < _resumeSelectionAfter) { [self traceScan:@"settling"]; return; }
    if (translate) _translateRequested = YES;
    if (!ReadSelectionTranslationEnabled() || !SelectionTranslationHasPermission()) {
        [self traceScan:ReadSelectionTranslationEnabled() ? @"permission" : @"disabled"];
        ++_scanRevision;
        _translateRequested = NO;
        [_model observeSelection:nil];
        return;
    }
    _model.automaticallyTranslates = ReadSelectionTranslationAutomatic();
    if (_reading) { [self traceScan:@"read-in-progress"]; return; }
    if (NSEvent.pressedMouseButtons) { [self traceScan:@"mouse-down"]; return; }
    if (!_translateRequested && ([self pointerInPanels] || _card.keyWindow)) { [self traceScan:@"popup-interaction"]; return; }
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    pid_t pid = front.processIdentifier;
    if (!pid || pid == NSProcessInfo.processInfo.processIdentifier) { [self traceScan:@"own-app"]; [_model observeSelection:nil]; return; }
    [self traceScan:@"reading"];
    _reading = YES;
    BOOL translateAfter = _translateRequested;
    _translateRequested = NO;
    NSUInteger revision = _scanRevision;
    NSPoint point = NSEvent.mouseLocation;
    CGFloat top = NSMaxY(NSScreen.screens.firstObject.frame);
    __weak SelectionOverlay *weakSelf = self;
    dispatch_async(_readerQueue, ^{
        TextSelection *selection = ReadTextSelection(pid, point, top);
        dispatch_async(dispatch_get_main_queue(), ^{
            SelectionOverlay *self = weakSelf;
            if (!self) return;
            self->_reading = NO;
            TraceSelectionEvent(@"read-result", @{@"pid":@(pid), @"present":@(selection != nil), @"length":@(selection.text.length), @"stale":@(self->_scanRevision != revision)});
            if (self->_model.suspended || self->_scanRevision != revision || NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier != pid) return;
            if (self->_translateRequested) { [self scanWithTranslation:YES]; return; }
            if (NSEvent.pressedMouseButtons || !ReadSelectionTranslationEnabled()) return;
            [self->_model observeSelection:selection];
            if (translateAfter) [self->_model translateWithPreference:ReadSelectionTranslationTarget()];
        });
    });
}
- (void)mouseEvent:(NSEvent *)event {
    if ([self pointerInPanels]) return;
    if (event.type == NSEventTypeLeftMouseDown) {
        _mouseDownPoint = NSEvent.mouseLocation;
        _mouseClickCount = event.clickCount;
    }
    if (event.type != NSEventTypeLeftMouseUp) [self close:nil];
    if (event.type == NSEventTypeLeftMouseUp) {
        NSPoint end = NSEvent.mouseLocation;
        if (_mouseClickCount > 1 || hypot(end.x - _mouseDownPoint.x, end.y - _mouseDownPoint.y) > 4)
            [_model observeSelection:nil];
        NSUInteger revision = _scanRevision;
        __weak SelectionOverlay *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            SelectionOverlay *self = weakSelf;
            if (self && self->_scanRevision == revision) [self scanWithTranslation:NO];
        });
    }
}
- (void)compositionActivityChanged {
    // Discard AX reads started before composition, including ones that finish after commit.
    ++_scanRevision;
    _translateRequested = NO;
    BOOL active = SelectionTranslationCompositionActive();
    TraceSelectionEvent(@"composition", @{@"active":@(active)});
    _model.suspended = active;
    // Allow the host to clear its marked range before reading selections again.
    _resumeSelectionAfter = active ? 0 : NSDate.timeIntervalSinceReferenceDate + 0.35;
}
- (void)start {
    __weak SelectionOverlay *weakSelf = self;
    _compositionObserver = [NSNotificationCenter.defaultCenter addObserverForName:SelectionTranslationCompositionDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        [weakSelf compositionActivityChanged];
    }];
    [self compositionActivityChanged];
    NSEventMask mask = NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp | NSEventMaskRightMouseDown | NSEventMaskScrollWheel;
    _globalMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:mask handler:^(NSEvent *event) { [weakSelf mouseEvent:event]; }];
    _localMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:mask handler:^NSEvent *(NSEvent *event) { [weakSelf mouseEvent:event]; return event; }];
    _activationObserver = [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidActivateApplicationNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        SelectionOverlay *self = weakSelf;
        if (self) { ++self->_scanRevision; [self->_model observeSelection:nil]; }
    }];
    _timer = [NSTimer timerWithTimeInterval:0.65 repeats:YES block:^(NSTimer *timer) { [weakSelf scanWithTranslation:NO]; }];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (void)showPreview {
    _preview = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 300) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    _preview.releasedWhenClosed = NO;
    _preview.title = L(@"{appName} Preview — select text and click Translate");
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:_preview.contentView.bounds];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    _previewText = [[NSTextView alloc] initWithFrame:scroll.bounds];
    _previewText.editable = NO;
    _previewText.selectable = YES;
    _previewText.font = [NSFont systemFontOfSize:18];
    _previewText.textContainerInset = NSMakeSize(20, 20);
    _previewText.string = @"Select this sentence to translate it into Chinese.\n\n选中这句话，点击旁边的“译”按钮，可以翻译成英文。\n\n这是只读文字，不需要输入框焦点。";
    _previewText.delegate = self;
    scroll.documentView = _previewText;
    [_preview.contentView addSubview:scroll];
    [_preview center]; [_preview makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [_previewText setSelectedRange:[_previewText.string rangeOfString:@"Select this sentence to translate it into Chinese."]];
    [self textViewDidChangeSelection:[NSNotification notificationWithName:NSTextViewDidChangeSelectionNotification object:_previewText]];
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--selection-result-preview"] && !_model.automaticallyTranslates)
        [_model translateWithPreference:@"auto"];
}
- (void)textViewDidChangeSelection:(NSNotification *)notification {
    NSRange range = _previewText.selectedRange;
    if (!range.length || NSMaxRange(range) > _previewText.string.length) { [_model observeSelection:nil]; return; }
    TextSelection *selection = [TextSelection new];
    selection.text = [_previewText.string substringWithRange:range];
    selection.identifier = NSStringFromRange(range);
    selection.processID = NSProcessInfo.processInfo.processIdentifier;
    selection.anchor = [_previewText firstRectForCharacterRange:range actualRange:NULL];
    [_model observeSelection:selection];
    _preview.title = [NSString stringWithFormat:L(@"{appName} Preview — %lu characters selected"), (unsigned long)range.length];
}
@end

void StartSelectionTranslation(void) {
    static SelectionOverlay *overlay;
    if (!overlay) { overlay = [SelectionOverlay new]; [overlay start]; }
}
void ShowSelectionTranslationPreview(void) {
    static SelectionOverlay *preview;
    if (!preview) preview = [SelectionOverlay new];
    [preview showPreview];
}
