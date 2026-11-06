#import "Core.h"
#import "SelectionTranslation.h"
#import <InputMethodKit/InputMethodKit.h>

NSStackView *CreateCompositionHeader(NSTextField *inputModeLabel) {
    NSTextField *shortcuts = [NSTextField labelWithString:L(@"Tab: translation · Enter: source")];
    shortcuts.font = [NSFont systemFontOfSize:11];
    shortcuts.textColor = NSColor.secondaryLabelColor;
    shortcuts.alignment = NSTextAlignmentRight;
    [shortcuts setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    [shortcuts setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *header = [NSStackView stackViewWithViews:@[inputModeLabel, shortcuts]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.distribution = NSStackViewDistributionFill;
    header.alignment = NSLayoutAttributeTop;
    header.spacing = 12;
    return header;
}

@interface CandidatePanel : NSPanel
@end
@implementation CandidatePanel
- (BOOL)canBecomeKey { return NO; }
- (BOOL)canBecomeMain { return NO; }
@end

@interface DualLineController : IMKInputController <SelectionTranslationCompositionOwner>
@end

@implementation DualLineController {
    Composition *_composition;
    CandidatePanel *_panel;
    CandidatePanel *_modePanel;
    NSTextField *_modeLabel;
    NSUInteger _modeNoticeRevision;
    SentenceView *_sentenceView;
    NSTextField *_englishLabel;
    NSStackView *_translationRow;
    NSTextField *_hintLabel;
    NSTextField *_inputModeLabel;
    CandidateListView *_candidates;
    BOOL _active;
    BOOL _palettesHidden;
    BOOL _renderingComposition;
    BOOL _selectionChecked;
    BOOL _usesMarkedText;
    NSString *_lastMarked;
    NSRange _lastMarkedSelection;
    NSAttributedString *_originalSelection;
    NSString *_interfaceLanguage;
}
- (instancetype)initWithServer:(IMKServer *)server delegate:(id)delegate client:(id)client {
    if ((self = [super initWithServer:server delegate:delegate client:client])) {
        _composition = [Composition new];
        [_composition synchronizeModifiers:NSEvent.modifierFlags];
        __weak DualLineController *weakSelf = self;
        _composition.changed = ^{ [weakSelf render]; };
        _composition.committed = ^(NSString *text) { [weakSelf insert:text]; };
        _composition.inputLanguageCommitted = ^(NSString *language) {
            [[NSUserDefaults standardUserDefaults] setObject:language forKey:@"lastInputLanguage"];
        };
        _composition.cancelled = ^{ [weakSelf restoreSelection]; };
        _composition.copyText = ^(NSString *text) {
            [NSPasteboard.generalPasteboard clearContents];
            [NSPasteboard.generalPasteboard setString:text forType:NSPasteboardTypeString];
        };
        _composition.pasteText = ^NSString *{ return [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString]; };
        [self createPanel];
        [self createModePanel];
    }
    return self;
}
- (NSTextField *)labelWithSize:(CGFloat)size color:(NSColor *)color {
    NSTextField *label = [NSTextField wrappingLabelWithString:@""];
    label.font = [NSFont systemFontOfSize:size];
    label.textColor = color;
    label.maximumNumberOfLines = 3;
    [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}
- (void)createPanel {
    _interfaceLanguage = CurrentInterfaceLanguage();
    _panel = [[CandidatePanel alloc] initWithContentRect:NSMakeRect(0, 0, 580, 210) styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    _panel.releasedWhenClosed = NO;
    _panel.hidesOnDeactivate = NO;
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    _panel.hasShadow = YES;
    _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    NSVisualEffectView *background = [[NSVisualEffectView alloc] initWithFrame:_panel.contentView.bounds];
    background.material = NSVisualEffectMaterialPopover;
    background.state = NSVisualEffectStateActive;
    background.wantsLayer = YES;
    background.layer.cornerRadius = 12;
    _panel.contentView = background;
    _sentenceView = [[SentenceView alloc] initWithFrame:NSMakeRect(0, 0, 420, 24)];
    __weak SentenceView *sentenceView = _sentenceView;
    _composition.moveSentenceCaret = ^NSUInteger(NSUInteger caret, NSInteger delta) {
        return sentenceView ? [sentenceView moveCaret:caret byLines:delta] : caret;
    };
    _englishLabel = [self labelWithSize:16 color:NSColor.labelColor];
    NSStackView *englishRow = CreateLanguageRow(L(@"EN"), _englishLabel);
    _translationRow = englishRow;
    _hintLabel = [self labelWithSize:11 color:NSColor.secondaryLabelColor];
    _inputModeLabel = [self labelWithSize:11 color:NSColor.secondaryLabelColor];
    NSStackView *header = CreateCompositionHeader(_inputModeLabel);
    _candidates = [[CandidateListView alloc] initWithFrame:NSZeroRect];
    __weak Composition *composition = _composition;
    _candidates.choose = ^(NSUInteger index) { [composition chooseCandidate:index]; };
    _candidates.changePage = ^(BOOL backward) { [composition changeCandidatePage:backward]; };
    _candidates.setExpanded = ^(BOOL expanded) { if (expanded) [composition expandCandidates]; else [composition collapseCandidates]; };
    NSBox *separator = [NSBox new];
    separator.boxType = NSBoxSeparator;
    NSStackView *stack = [NSStackView stackViewWithViews:@[header, _sentenceView, _candidates, separator, englishRow, _hintLabel]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [background addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:background.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:background.bottomAnchor constant:-12],
        [_sentenceView.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [englishRow.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [_hintLabel.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [header.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [separator.widthAnchor constraintEqualToAnchor:stack.widthAnchor]
    ]];
}
- (void)createModePanel {
    _modePanel = [[CandidatePanel alloc] initWithContentRect:NSMakeRect(0, 0, 230, 42) styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    _modePanel.releasedWhenClosed = NO;
    _modePanel.hidesOnDeactivate = NO;
    _modePanel.opaque = NO;
    _modePanel.backgroundColor = NSColor.clearColor;
    _modePanel.hasShadow = YES;
    _modePanel.ignoresMouseEvents = YES;
    _modePanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    NSVisualEffectView *background = [[NSVisualEffectView alloc] initWithFrame:_modePanel.contentView.bounds];
    background.material = NSVisualEffectMaterialPopover;
    background.state = NSVisualEffectStateActive;
    background.wantsLayer = YES;
    background.layer.cornerRadius = 10;
    _modePanel.contentView = background;
    _modeLabel = [NSTextField labelWithString:@""];
    _modeLabel.font = [NSFont systemFontOfSize:16 weight:NSFontWeightMedium];
    _modeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [background addSubview:_modeLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_modeLabel.centerXAnchor constraintEqualToAnchor:background.centerXAnchor],
        [_modeLabel.centerYAnchor constraintEqualToAnchor:background.centerYAnchor]
    ]];
}
- (void)hideModeNotice {
    ++_modeNoticeRevision;
    [_modePanel orderOut:nil];
}
- (void)modeChanged {
    if (_composition.hasEditingSession) { [self hideModeNotice]; return; }
    _modeLabel.stringValue = _composition.inputModeDescription;
    [self positionPanel:_modePanel width:MAX(80, _modeLabel.intrinsicContentSize.width + 32) height:42];
    NSUInteger revision = ++_modeNoticeRevision;
    __weak DualLineController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1200 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        DualLineController *self = weakSelf;
        if (self && self->_modeNoticeRevision == revision) [self hideModeNotice];
    });
}
- (NSUInteger)recognizedEvents:(id)sender {
    return NSEventMaskKeyDown | NSEventMaskFlagsChanged | NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown;
}
- (BOOL)handleEvent:(NSEvent *)event client:(id)sender {
    if (!_composition) return NO;
    if (event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeRightMouseDown || event.type == NSEventTypeOtherMouseDown) {
        [_composition cancel];
        [self hideModeNotice];
        return NO;
    }
    if (event.type != NSEventTypeKeyDown && event.type != NSEventTypeFlagsChanged) return NO;
    _active = YES;
    if (event.type == NSEventTypeKeyDown) _palettesHidden = NO;
    NSString *previousLanguage = _composition.inputLanguage;
    BOOL wasEditing = _composition.hasEditingSession;
    BOOL handled;
    NSEventModifierFlags flags = event.modifierFlags;
    if (event.type == NSEventTypeFlagsChanged) handled = [_composition handleModifiers:flags];
    else handled = [_composition handlePhysicalKey:event.keyCode text:event.characters ?: @"" modifiers:flags];
    if (![previousLanguage isEqual:_composition.inputLanguage]) [self modeChanged];
    else if (wasEditing && !_composition.hasEditingSession) [self hideModeNotice];
    return handled;
}
- (void)activateServer:(id)sender {
    [super activateServer:sender];
    _active = YES;
    _palettesHidden = NO;
    [_composition synchronizeModifiers:NSEvent.modifierFlags];
    _composition.candidateColumns = ReadCandidateColumns();
    _composition.engine.learningEnabled = ReadLearningEnabled();
    [[self client] overrideKeyboardWithKeyboardNamed:@"com.apple.keylayout.ABC"];
}
- (void)deactivateServer:(id)sender {
    [_composition cancel];
    _active = NO;
    [_panel orderOut:nil];
    [self hideModeNotice];
    [super deactivateServer:sender];
}
- (void)commitComposition:(id)sender {
    // Focus changes must never submit an unfinished sentence or a late translation.
    [_composition cancel];
}
- (void)hidePalettes {
    _palettesHidden = YES;
    [_panel orderOut:nil];
    [self hideModeNotice];
    SetSelectionTranslationCompositionActive(self, NO);
}
- (void)inputControllerWillClose {
    [_composition cancel];
    _active = NO;
    [_panel close];
    [self hideModeNotice];
    [_modePanel close];
    [super inputControllerWillClose];
}
- (void)dealloc { SetSelectionTranslationCompositionActive(self, NO); }
- (void)clearTracking {
    _lastMarked = nil;
    _lastMarkedSelection = NSMakeRange(NSNotFound, 0);
    _originalSelection = nil;
    _selectionChecked = NO;
    _usesMarkedText = NO;
}
- (void)restoreSelection {
    if (_usesMarkedText && _lastMarked != nil) {
        if (_originalSelection.length) [[self client] insertText:_originalSelection replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
        else [[self client] setMarkedText:@"" selectionRange:NSMakeRange(0, 0) replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
    }
    [self clearTracking];
}
- (void)insert:(NSString *)text {
    if (!_active) return;
    [[self client] insertText:text replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
    [self clearTracking];
}
- (BOOL)selectionTranslationCompositionActive {
    return _active && !_palettesHidden && (_composition.pendingKeyboardText.length ||
        (_composition.hasEditingSession && (_renderingComposition || _panel.visible)));
}
- (void)render {
    if (![_interfaceLanguage isEqual:CurrentInterfaceLanguage()]) {
        [_panel orderOut:nil];
        [self createPanel];
    }
    // Marked text can appear as AXSelectedText in the host, even without a user selection.
    _renderingComposition = _active && !_palettesHidden && (_composition.hasEditingSession || _composition.pendingKeyboardText.length);
    SetSelectionTranslationCompositionActive(self, _renderingComposition);
    if (!_renderingComposition) {
        if (!_composition.hasEditingSession && _lastMarked != nil) [self restoreSelection];
        [_panel orderOut:nil];
        return;
    }
    id<IMKTextInput> client = [self client];
    NSString *preedit = _composition.engine.preedit;
    NSString *marked = _composition.markedText;
    NSRange selectionInMarked = _composition.markedSelection;
    if (!_selectionChecked) {
        _selectionChecked = YES;
        NSRange selection = [client selectedRange];
        if (selection.location != NSNotFound && selection.length != NSNotFound) {
            if (selection.length) _originalSelection = [client attributedSubstringFromRange:selection];
            _usesMarkedText = !selection.length || _originalSelection.length == selection.length;
        }
    }
    if (_usesMarkedText && (![_lastMarked isEqual:marked] || !NSEqualRanges(_lastMarkedSelection, selectionInMarked))) {
        [client setMarkedText:marked selectionRange:selectionInMarked replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
        _lastMarked = marked;
        _lastMarkedSelection = selectionInMarked;
    }
    if (!_composition.hasComposition) {
        // Empty drafts keep undo history without keeping the panel visible.
        // Native dead-key text also stays in the host without a translation panel.
        [_panel orderOut:nil];
        _renderingComposition = NO;
        SetSelectionTranslationCompositionActive(self, self.selectionTranslationCompositionActive);
        return;
    }
    [_sentenceView updateWithComposition:_composition];
    [self hideModeNotice];
    _inputModeLabel.stringValue = _composition.inputModeDescription;
    NSRect caret = NSZeroRect;
    [client attributesForCharacterIndex:0 lineHeightRectangle:&caret];
    NSRect visible = [self screenForCaret:caret].visibleFrame;
    _candidates.maximumWidth = MAX(300, visible.size.width - 60);
    _candidates.maximumHeight = MAX(120, visible.size.height - 300);
    [_candidates updateWithPage:_composition.engine.candidatePage expanded:_composition.candidatesExpanded columns:_composition.candidateColumns];
    _englishLabel.stringValue = _composition.english.length ? _composition.english : L(@"Waiting for translation…");
    UpdateTranslationLanguageRow(_translationRow, _composition.translationTargetLanguage);
    _englishLabel.textColor = _composition.english.length ? NSColor.labelColor : NSColor.secondaryLabelColor;
    BOOL needsConfirmation = [@[
        L(@"Confirm Chinese candidates with Space or a number first"),
        L(@"Confirm Chinese candidates before entering punctuation or numbers"),
        L(@"Press Tab / Enter to insert, or Esc to cancel the draft")
    ] containsObject:_composition.hint ?: @""];
    _hintLabel.stringValue = preedit.length && !_composition.markedSelection.length && ![_composition.hint containsString:@"⌘"] && !needsConfirmation
        ? (_composition.candidatesExpanded ? L(@"Arrows: choose · Space: confirm · Enter / tap Shift: keep letters · Esc: collapse") : [NSString stringWithFormat:L(@"← → choose · Space / 1–%ld confirm · ↑ ↓ expand · Enter / tap Shift: keep letters"), (long)_composition.candidateColumns]) : _composition.hint;
    CGFloat width = MIN(visible.size.width - 20, MAX(420, _candidates.contentWidth) + 28);
    [_panel setContentSize:NSMakeSize(width, _panel.contentView.bounds.size.height)];
    [_panel.contentView layoutSubtreeIfNeeded];
    CGFloat height = MAX(120, MIN(visible.size.height - 20, _panel.contentView.fittingSize.height));
    [self positionPanel:_panel width:width height:height];
    _renderingComposition = NO;
    SetSelectionTranslationCompositionActive(self, self.selectionTranslationCompositionActive);
}
- (NSScreen *)screenForCaret:(NSRect)caret {
    // IMK reports candidate placement in AppKit screen coordinates.
    NSScreen *screen = nil;
    for (NSScreen *candidate in NSScreen.screens) {
        if (NSIntersectsRect(candidate.frame, NSInsetRect(caret, -1, -1))) { screen = candidate; break; }
    }
    return screen ?: NSScreen.mainScreen;
}
- (void)positionPanel:(NSPanel *)panel width:(CGFloat)width height:(CGFloat)height {
    if (!_active || _palettesHidden) return;
    id<IMKTextInput> client = [self client];
    NSRect caret = NSZeroRect;
    [client attributesForCharacterIndex:0 lineHeightRectangle:&caret];
    NSRect visible = [self screenForCaret:caret].visibleFrame;
    CGFloat x = MAX(visible.origin.x, MIN(caret.origin.x, NSMaxX(visible) - width));
    CGFloat y = caret.origin.y - height - 6;
    if (y < visible.origin.y) y = NSMaxY(caret) + 6;
    y = MAX(visible.origin.y, MIN(y, NSMaxY(visible) - height));
    [panel setFrame:NSMakeRect(x, y, width, height) display:YES];
    panel.level = MAX(NSFloatingWindowLevel, [client windowLevel] + 1);
    [panel orderFrontRegardless];
}
- (void)choose:(NSButton *)sender { [_composition chooseCandidate:sender.tag]; }
- (void)retry:(id)sender { [_composition retry]; }
- (void)cancel:(id)sender { [_composition cancel]; }
- (void)settings:(id)sender { [_composition cancel]; ShowSettings(); }
- (NSMenu *)menu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:AppDisplayName()];
    NSString *language = InputLanguageForModifiers(NSEvent.modifierFlags);
    for (NSMenuItem *item in CreateInputLanguageMenuItems(language)) [menu addItem:item];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:L(@"Settings…") action:@selector(settings:) keyEquivalent:@""];
    if (_composition.chinese.length) [menu addItemWithTitle:L(@"Translate this draft again") action:@selector(retry:) keyEquivalent:@""];
    [menu addItemWithTitle:L(@"Cancel this draft") action:@selector(cancel:) keyEquivalent:@""];
    return menu;
}
@end
