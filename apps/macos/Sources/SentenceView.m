#import "Core.h"

static CGFloat LanguageBadgeWidth(void) {
    // The source and target share one width, even with a longer localized source label.
    return MAX(40, ceil([L(@"Source") sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:11 weight:NSFontWeightMedium]}].width) + 16);
}

@interface LanguageBadgeView : NSView
@property(nonatomic, strong) NSTextField *label;
- (instancetype)initWithTitle:(NSString *)title;
@end

@implementation LanguageBadgeView
- (instancetype)initWithTitle:(NSString *)title {
    if ((self = [super initWithFrame:NSMakeRect(0, 0, LanguageBadgeWidth(), 22)])) {
        NSTextField *label = [NSTextField labelWithString:title];
        _label = label;
        label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        label.textColor = NSColor.secondaryLabelColor;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor]
        ]];
        [self setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
        [self setContentCompressionResistancePriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    return self;
}
- (NSSize)intrinsicContentSize { return NSMakeSize(LanguageBadgeWidth(), 22); }
- (void)drawRect:(NSRect)dirtyRect {
    [NSColor.quaternaryLabelColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:5 yRadius:5] fill];
}
@end

NSView *CreateLanguageBadge(NSString *title) { return [[LanguageBadgeView alloc] initWithTitle:title]; }

void UpdateTranslationLanguageRow(NSStackView *row, NSString *language) {
    LanguageBadgeView *badge = (LanguageBadgeView *)row.arrangedSubviews.firstObject;
    badge.label.stringValue = TranslationLanguageBadge(language);
    badge.toolTip = TranslationLanguageName(language);
}

NSStackView *CreateLanguageRow(NSString *title, NSTextField *text) {
    NSView *badge = CreateLanguageBadge(title);
    NSView *textContainer = [NSView new];
    text.translatesAutoresizingMaskIntoConstraints = NO;
    [textContainer addSubview:text];
    CGFloat lineHeight = ceil([[NSLayoutManager new] defaultLineHeightForFont:text.font]);
    // Center against the first line, not the height of the whole wrapped paragraph.
    CGFloat topInset = MAX(0, (badge.intrinsicContentSize.height - lineHeight) / 2);
    [NSLayoutConstraint activateConstraints:@[
        [text.leadingAnchor constraintEqualToAnchor:textContainer.leadingAnchor],
        [text.trailingAnchor constraintEqualToAnchor:textContainer.trailingAnchor],
        [text.topAnchor constraintEqualToAnchor:textContainer.topAnchor constant:topInset],
        [text.bottomAnchor constraintEqualToAnchor:textContainer.bottomAnchor]
    ]];
    NSStackView *row = [NSStackView stackViewWithViews:@[badge, textContainer]];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.distribution = NSStackViewDistributionFill;
    row.alignment = NSLayoutAttributeTop;
    // Align with the sentence's eight-point gap plus its two-point text inset.
    row.spacing = 10;
    [badge.widthAnchor constraintEqualToConstant:LanguageBadgeWidth()].active = YES;
    [badge.heightAnchor constraintEqualToConstant:22].active = YES;
    return row;
}

@interface SentenceTextView : NSTextView
@property(nonatomic) BOOL showsCaret;
@property(nonatomic, readonly) NSRect caretRect;
@property(nonatomic) NSRange displayedSelection;
@end

@implementation SentenceTextView
// IMK retains keyboard focus in the host. This view only renders and navigates text.
- (BOOL)acceptsFirstResponder { return NO; }
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (BOOL)shouldDrawInsertionPoint { return NO; }
- (NSRange)accessibilitySelectedTextRange { return _displayedSelection; }
- (NSArray<NSValue *> *)accessibilitySelectedTextRanges { return @[[NSValue valueWithRange:_displayedSelection]]; }
- (NSString *)accessibilitySelectedText { return [self.string substringWithRange:_displayedSelection]; }
- (NSRect)caretRect {
    [self.layoutManager ensureLayoutForTextContainer:self.textContainer];
    NSUInteger count = 0;
    NSRectArray rects = [self.layoutManager rectArrayForCharacterRange:NSMakeRange(self.selectedRange.location, 0)
        withinSelectedCharacterRange:NSMakeRange(NSNotFound, 0) inTextContainer:self.textContainer rectCount:&count];
    NSRect rect = count ? rects[0] : self.layoutManager.extraLineFragmentRect;
    rect.origin.x += self.textContainerOrigin.x;
    rect.origin.y += self.textContainerOrigin.y;
    rect.size.width = 1;
    if (!rect.size.height) rect.size.height = [self.layoutManager defaultLineHeightForFont:self.font];
    return rect;
}
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    if (_showsCaret && !self.selectedRange.length) {
        [NSColor.controlAccentColor setFill];
        NSRectFill(self.caretRect);
    }
}
@end

@implementation SentenceView {
    NSView *_languageBadge;
    NSScrollView *_scroll;
    SentenceTextView *_sentence;
    CGFloat _contentHeight;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _languageBadge = CreateLanguageBadge(L(@"Source"));
        [self addSubview:_languageBadge];
        _scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        _scroll.drawsBackground = NO;
        _scroll.borderType = NSNoBorder;
        _scroll.contentView.drawsBackground = NO;
        _sentence = [[SentenceTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 24)];
        _sentence.font = [NSFont systemFontOfSize:17];
        _sentence.textColor = NSColor.labelColor;
        _sentence.drawsBackground = NO;
        _sentence.richText = NO;
        // Native moveUp:/moveDown: require editable text, but hit testing and focus are disabled.
        _sentence.editable = YES;
        _sentence.selectable = YES;
        _sentence.allowsUndo = NO;
        _sentence.verticallyResizable = YES;
        _sentence.horizontallyResizable = NO;
        _sentence.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
        _sentence.textContainerInset = NSMakeSize(2, 2);
        _sentence.textContainer.lineFragmentPadding = 0;
        _sentence.textContainer.widthTracksTextView = YES;
        _sentence.textContainer.heightTracksTextView = NO;
        _sentence.selectedTextAttributes = @{NSBackgroundColorAttributeName:NSColor.selectedTextBackgroundColor,
            NSForegroundColorAttributeName:NSColor.selectedTextColor};
        _scroll.documentView = _sentence;
        [self addSubview:_scroll];
        _contentHeight = 24;
    }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (NSTextView *)textView { return _sentence; }
- (BOOL)showsCaret { return _sentence.showsCaret; }
- (NSRect)caretRect { return _sentence.caretRect; }
- (NSRange)selectionRange { return _sentence.displayedSelection; }
- (NSSize)intrinsicContentSize { return NSMakeSize(NSViewNoIntrinsicMetric, _contentHeight); }
- (void)layout {
    [super layout];
    CGFloat leading = _languageBadge.frame.size.width + 8;
    CGFloat width = MAX(40, self.bounds.size.width - leading);
    [_languageBadge setFrameOrigin:NSMakePoint(0, 1)];
    _scroll.frame = NSMakeRect(leading, 0, width, self.bounds.size.height);
    [_sentence setFrameSize:NSMakeSize(width, MAX(_contentHeight, _sentence.frame.size.height))];
    _sentence.textContainer.containerSize = NSMakeSize(MAX(1, width - 4), CGFLOAT_MAX);
    NSLayoutManager *manager = _sentence.layoutManager;
    [manager ensureLayoutForTextContainer:_sentence.textContainer];
    CGFloat lineHeight = [manager defaultLineHeightForFont:_sentence.font];
    CGFloat textHeight = MAX(NSMaxY([manager usedRectForTextContainer:_sentence.textContainer]), NSMaxY(manager.extraLineFragmentRect));
    CGFloat documentHeight = ceil(MAX(lineHeight, textHeight) + 4);
    CGFloat height = MIN(documentHeight, ceil(lineHeight * 3 + 4));
    if (_contentHeight != height) {
        _contentHeight = height;
        [self invalidateIntrinsicContentSize];
    }
    [_sentence setFrameSize:NSMakeSize(width, MAX(documentHeight, self.bounds.size.height))];
    [_sentence scrollRectToVisible:_sentence.caretRect];
}
- (void)updateWithComposition:(Composition *)composition {
    BOOL changed = ![_sentence.string isEqual:composition.markedText];
    if (changed) _sentence.string = composition.markedText;
    BOOL showsCaret = !composition.engine.preedit.length && !composition.markedSelection.length;
    // Keep the native insertion point at the active endpoint so vertical moves retain
    // their preferred column. Selection colors do not affect glyph layout or wrapping.
    NSRange caret = NSMakeRange(composition.markedCaret, 0);
    if (changed || !NSEqualRanges(_sentence.selectedRange, caret)) [_sentence setSelectedRange:caret];
    NSRange selection = composition.markedSelection;
    if (changed || !NSEqualRanges(_sentence.displayedSelection, selection)) {
        NSLayoutManager *manager = _sentence.layoutManager;
        NSRange all = NSMakeRange(0, _sentence.string.length);
        [manager removeTemporaryAttribute:NSBackgroundColorAttributeName forCharacterRange:all];
        [manager removeTemporaryAttribute:NSForegroundColorAttributeName forCharacterRange:all];
        if (selection.length) [manager addTemporaryAttributes:@{
            NSBackgroundColorAttributeName:NSColor.selectedTextBackgroundColor,
            NSForegroundColorAttributeName:NSColor.selectedTextColor} forCharacterRange:selection];
        _sentence.displayedSelection = selection;
    }
    _sentence.showsCaret = showsCaret;
    _sentence.needsDisplay = YES;
    self.needsLayout = YES;
}
- (NSUInteger)moveCaret:(NSUInteger)caret byLines:(NSInteger)delta {
    [self layoutSubtreeIfNeeded];
    NSRange selection = NSMakeRange(MIN(caret, _sentence.string.length), 0);
    if (!delta || !NSEqualRanges(_sentence.selectedRange, selection)) [_sentence setSelectedRange:selection];
    if (delta < 0) [_sentence moveUp:nil];
    else if (delta > 0) [_sentence moveDown:nil];
    [_sentence scrollRectToVisible:_sentence.caretRect];
    _sentence.needsDisplay = YES;
    return _sentence.selectedRange.location;
}
@end
