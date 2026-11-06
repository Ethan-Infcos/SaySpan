#import "Core.h"

@interface CandidateChoiceButton : NSButton
@property(nonatomic) BOOL selectedCandidate;
@end

static NSDictionary *CandidateTextAttributes(BOOL selected) {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.lineBreakMode = NSLineBreakByCharWrapping;
    style.alignment = NSTextAlignmentLeft;
    return @{
        NSFontAttributeName:[NSFont systemFontOfSize:15 weight:selected ? NSFontWeightSemibold : NSFontWeightRegular],
        NSForegroundColorAttributeName:selected ? NSColor.whiteColor : NSColor.labelColor,
        NSParagraphStyleAttributeName:style
    };
}

@implementation CandidateChoiceButton
- (void)drawRect:(NSRect)dirtyRect {
    NSColor *background = _selectedCandidate ? NSColor.controlAccentColor : NSColor.controlBackgroundColor;
    [background setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6 yRadius:6] fill];
    [self.title drawWithRect:NSInsetRect(self.bounds, 8, 5)
                    options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                 attributes:CandidateTextAttributes(_selectedCandidate)];
}
@end

@interface CandidateRows : NSStackView
@end
@implementation CandidateRows
- (BOOL)isFlipped { return YES; }
@end

@implementation CandidateListView {
    NSStackView *_choices;
    NSScrollView *_scroll;
    NSLayoutConstraint *_scrollWidth;
    NSLayoutConstraint *_scrollHeight;
    NSTextField *_pageLabel;
    NSButton *_previous;
    NSButton *_next;
    NSButton *_more;
    NSStackView *_paging;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.orientation = NSUserInterfaceLayoutOrientationVertical;
        self.alignment = NSLayoutAttributeLeading;
        self.spacing = 8;
        _maximumWidth = 1000;
        _maximumHeight = 320;
        _choices = [CandidateRows stackViewWithViews:@[]];
        _choices.orientation = NSUserInterfaceLayoutOrientationVertical;
        _choices.alignment = NSLayoutAttributeLeading;
        _choices.spacing = 6;
        _scroll = [NSScrollView new];
        _scroll.drawsBackground = NO;
        _scroll.hasVerticalScroller = YES;
        _scroll.autohidesScrollers = YES;
        _scroll.scrollerStyle = NSScrollerStyleOverlay;
        _scroll.documentView = _choices;
        _scrollWidth = [_scroll.widthAnchor constraintEqualToConstant:1];
        _scrollHeight = [_scroll.heightAnchor constraintEqualToConstant:1];
        _scrollWidth.active = _scrollHeight.active = YES;
        _pageLabel = [NSTextField labelWithString:@""];
        _pageLabel.textColor = NSColor.secondaryLabelColor;
        _previous = [NSButton buttonWithTitle:@"‹" target:self action:@selector(previous:)];
        _next = [NSButton buttonWithTitle:@"›" target:self action:@selector(next:)];
        _previous.toolTip = L(@"Previous page (Page Up)");
        _next.toolTip = L(@"Next page (Page Down)");
        _previous.accessibilityLabel = L(@"Previous page");
        _next.accessibilityLabel = L(@"Next page");
        NSButton *collapse = [NSButton buttonWithTitle:L(@"Collapse Esc") target:self action:@selector(collapse:)];
        _more = [NSButton buttonWithTitle:L(@"More candidates ↓") target:self action:@selector(expand:)];
        _paging = [NSStackView stackViewWithViews:@[_previous, _pageLabel, _next, collapse]];
        _paging.spacing = 10;
        [self addArrangedSubview:_scroll];
        [self addArrangedSubview:_more];
        [self addArrangedSubview:_paging];
    }
    return self;
}
- (void)updateWithPage:(CandidatePage *)page expanded:(BOOL)expanded columns:(NSInteger)columns {
    columns = MAX(MinimumCandidateColumns, MIN(MaximumCandidateColumns, columns));
    // Measure the entire page in both states, so expanding or moving the highlight
    // never changes a column's width. Use the wider selected font for measurement.
    NSUInteger columnCount = MIN((NSUInteger)columns, page.candidates.count);
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    CGFloat widths[MaximumCandidateColumns] = {0};
    for (NSUInteger index = 0; index < page.candidates.count; index++) {
        NSString *text = page.candidates[index];
        NSString *title = index < 9 ? [NSString stringWithFormat:@"%lu. %@", index + 1, text] : text;
        [titles addObject:title];
        NSUInteger column = index % columns;
        widths[column] = MAX(widths[column], MAX(48, ceil([title sizeWithAttributes:CandidateTextAttributes(YES)].width) + 20));
    }
    CGFloat gap = columnCount ? 6 * (columnCount - 1) : 0;
    CGFloat available = MAX(columnCount * 48, _maximumWidth - gap);
    CGFloat natural = 0;
    for (NSUInteger column = 0; column < columnCount; column++) natural += widths[column];
    if (natural > available) {
        // Cap only the wide columns; short candidates keep their natural width.
        CGFloat low = 48, high = available;
        for (NSUInteger iteration = 0; iteration < 40; iteration++) {
            CGFloat cap = (low + high) / 2, total = 0;
            for (NSUInteger column = 0; column < columnCount; column++) total += MIN(widths[column], cap);
            if (total > available) high = cap; else low = cap;
        }
        for (NSUInteger column = 0; column < columnCount; column++) widths[column] = floor(MIN(widths[column], low));
    }
    _contentWidth = gap;
    for (NSUInteger column = 0; column < columnCount; column++) _contentWidth += widths[column];
    for (NSView *view in _choices.arrangedSubviews.copy) {
        [_choices removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    NSUInteger count = expanded ? page.candidates.count : MIN((NSUInteger)columns, page.candidates.count);
    NSStackView *row;
    CandidateChoiceButton *selectedButton;
    CGFloat totalHeight = 0;
    for (NSUInteger index = 0; index < count; index++) {
        if (index % columns == 0) {
            row = [NSStackView stackViewWithViews:@[]];
            row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
            row.spacing = 6;
            [_choices addArrangedSubview:row];
            CGFloat height = 30;
            for (NSUInteger item = index; item < MIN(index + columns, count); item++) {
                NSRect bounds = [titles[item] boundingRectWithSize:NSMakeSize(widths[item % columns] - 16, CGFLOAT_MAX)
                    options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading attributes:CandidateTextAttributes(YES)];
                height = MAX(height, ceil(bounds.size.height) + 10);
            }
            [row.heightAnchor constraintEqualToConstant:height].active = YES;
            totalHeight += height + (index ? 6 : 0);
        }
        NSString *text = page.candidates[index];
        CandidateChoiceButton *button = [CandidateChoiceButton buttonWithTitle:titles[index] target:self action:@selector(chooseCandidate:)];
        button.tag = index;
        button.bordered = NO;
        button.selectedCandidate = index == (NSUInteger)page.highlighted;
        if (button.selectedCandidate) selectedButton = button;
        button.accessibilityLabel = button.title;
        button.accessibilityValue = button.selectedCandidate ? L(@"Highlighted candidate") : @"";
        button.toolTip = text;
        [row addArrangedSubview:button];
        [button.widthAnchor constraintEqualToConstant:widths[index % columns]].active = YES;
        [button.heightAnchor constraintEqualToAnchor:row.heightAnchor].active = YES;
    }
    _scrollWidth.constant = MAX(1, _contentWidth);
    _scrollHeight.constant = MAX(1, MIN(totalHeight, _maximumHeight));
    _choices.frame = NSMakeRect(0, 0, MAX(1, _contentWidth), totalHeight);
    [_choices layoutSubtreeIfNeeded];
    if (selectedButton) [_choices scrollRectToVisible:[selectedButton convertRect:selectedButton.bounds toView:_choices]];
    self.hidden = !page.candidates.count;
    _pageLabel.stringValue = [NSString stringWithFormat:L(@"Page %ld"), (long)page.index + 1];
    _previous.enabled = page.hasPreviousPage;
    _next.enabled = page.hasNextPage;
    _more.hidden = expanded;
    _paging.hidden = !expanded;
}
- (void)chooseCandidate:(NSButton *)sender { if (_choose) _choose(sender.tag); }
- (void)previous:(id)sender { if (_changePage) _changePage(YES); }
- (void)next:(id)sender { if (_changePage) _changePage(NO); }
- (void)expand:(id)sender { if (_setExpanded) _setExpanded(YES); }
- (void)collapse:(id)sender { if (_setExpanded) _setExpanded(NO); }
@end
