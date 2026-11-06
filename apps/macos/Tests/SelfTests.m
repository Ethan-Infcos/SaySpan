#import "Core.h"

static int failures;
static int checks;
static void Check(BOOL condition, NSString *message) {
    checks++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); }
}
static void Pump(NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (end.timeIntervalSinceNow > 0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
static void Type(Composition *composition, NSString *text) {
    for (NSUInteger i = 0; i < text.length; i++) [composition handleKey:0 text:[text substringWithRange:NSMakeRange(i, 1)] modifiers:0];
}
static void Confirm(Composition *composition) {
    for (int i = 0; i < 20 && composition.engine.preedit.length; i++) [composition handleKey:49 text:@" " modifiers:0];
}
static Composition *NewComposition(void) {
    Composition *composition = [Composition new];
    Check(composition != nil, @"Rime schema loads");
    // Most fixtures exercise Chinese editing after the user has switched modes.
    [composition synchronizeModifiers:0];
    composition.engine.learningEnabled = NO;
    composition.service = ^(NSString *text, TranslationCompletion completion) { completion(@"Hello", nil); };
    composition.candidateColumns = DefaultCandidateColumns;
    return composition;
}

static SentenceView *BindSentenceView(Composition *composition, CGFloat width) {
    SentenceView *view = [[SentenceView alloc] initWithFrame:NSMakeRect(0, 0, width, 24)];
    __weak Composition *weakComposition = composition;
    __weak SentenceView *weakView = view;
    composition.changed = ^{
        [weakView updateWithComposition:weakComposition];
        [weakView layoutSubtreeIfNeeded];
        [weakView setFrameSize:NSMakeSize(width, weakView.intrinsicContentSize.height)];
        [weakView layoutSubtreeIfNeeded];
    };
    composition.moveSentenceCaret = ^NSUInteger(NSUInteger caret, NSInteger delta) {
        return [weakView moveCaret:caret byLines:delta];
    };
    composition.changed();
    return view;
}

static NSUInteger FindCandidate(Composition *composition, NSString *word) {
    [composition expandCandidates];
    for (NSUInteger page = 0; page < 100; page++) {
        NSUInteger index = [composition.engine.candidates indexOfObject:word];
        if (index != NSNotFound) return index;
        if (!composition.engine.candidatePage.hasNextPage) break;
        [composition changeCandidatePage:NO];
    }
    return NSNotFound;
}

int RunLearningTests(BOOL verifyPersistence) {
    @autoreleasepool {
        NSString *directory = NSProcessInfo.processInfo.environment[@"DUALIME_USER_DIR"];
        NSString *personal = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/DualLineIME"];
        if (!directory.length || [[directory stringByResolvingSymlinksInPath] isEqual:[personal stringByResolvingSymlinksInPath]]) {
            fprintf(stderr, "Learning tests require an isolated DUALIME_USER_DIR.\n");
            return 1;
        }
        NSString *fixturePath = [directory stringByAppendingPathComponent:@"learning-test.plist"];
        NSDictionary *fixture = [NSDictionary dictionaryWithContentsOfFile:fixturePath];
        if (!verifyPersistence && fixture) {
            fprintf(stderr, "Use a fresh directory for the learning write test.\n");
            return 1;
        }
        Composition *c = NewComposition();
        Check(!c.engine.learningEnabled, @"The static schema disables learning");
        NSString *spelling = @"shishi";
        NSString *word = @"史诗";
        NSString *phrase = @"史诗星河";
        Type(c, spelling);
        NSString *baseFirst = c.engine.candidates.firstObject;
        NSUInteger index = FindCandidate(c, word);
        NSInteger baseRank = index == NSNotFound ? -1 : c.engine.candidatePage.index * 15 + index;
        Check(baseRank > 0 && ![baseFirst isEqual:word], @"The learning target initially ranks below the first dictionary candidate");
        [c cancel];
        c.engine.learningEnabled = YES;
        Check(c.engine.learningEnabled, @"The learning schema can be enabled without redeployment");
        if (verifyPersistence) {
            Check([fixture[@"word"] isEqual:word], @"The prior process completed the isolated learning fixture");
            Type(c, spelling);
            Check([c.engine.candidates.firstObject isEqual:word], @"Learned word ranking survives a full process restart");
            [c cancel]; Type(c, @"shishixinghe");
            Check([c.engine.candidates.firstObject isEqual:phrase], @"A learned multi-word phrase survives a full process restart");
            [c cancel];
        } else {
            for (NSUInteger repetition = 0; repetition < 8; repetition++) {
                Type(c, spelling);
                index = FindCandidate(c, word);
                Check(index != NSNotFound, @"The target remains selectable while learning");
                if (index == NSNotFound) break;
                [c chooseCandidate:index];
                Check([c.chinese isEqual:word], @"Learning preserves the exact selected Chinese word");
                [c commitChinese];
            }
            Type(c, spelling);
            Check([c.engine.candidates.firstObject isEqual:word], @"Repeated selections promote the chosen word to first place");
            [c cancel];
            Type(c, @"shishixinghe");
            index = FindCandidate(c, word);
            Check(index != NSNotFound, @"A custom phrase can begin with an explicitly chosen shorter word");
            if (index != NSNotFound) [c chooseCandidate:index];
            index = FindCandidate(c, @"星河");
            Check(index != NSNotFound, @"The remaining phrase segment can be selected independently");
            if (index != NSNotFound) [c chooseCandidate:index];
            Check([c.chinese isEqual:phrase], @"Segment choices combine into the intended phrase");
            [c commitChinese];
            Type(c, @"shishixinghe");
            Check([c.engine.candidates.firstObject isEqual:phrase], @"The selected multi-word phrase becomes a reusable candidate");
            [c cancel];
        }
        c.engine.learningEnabled = NO;
        Type(c, spelling);
        Check([c.engine.candidates.firstObject isEqual:baseFirst], @"Disabling memory restores the base dictionary order");
        [c cancel];
        for (NSUInteger repetition = 0; repetition < 8; repetition++) {
            Type(c, spelling); Confirm(c); [c commitChinese];
        }
        c.engine.learningEnabled = YES;
        Type(c, spelling);
        Check([c.engine.candidates.firstObject isEqual:word], @"Selections while disabled do not change the saved ranking, and re-enabling restores it");
        [c cancel];
        for (NSUInteger repetition = 0; repetition < 8; repetition++) {
            Type(c, spelling);
            index = FindCandidate(c, baseFirst);
            if (index != NSNotFound) [c.engine moveHighlight:(NSInteger)index - c.engine.highlighted];
            [c cancel];
        }
        Type(c, spelling);
        Check([c.engine.candidates.firstObject isEqual:word], @"Browsing and cancelling without selection does not train the highlighted word");
        [c cancel];
        if (!verifyPersistence && !failures) {
            Check([@{@"word":word, @"phrase":phrase} writeToFile:fixturePath atomically:YES], @"The persistence fixture is written for a separate process");
            printf("Learning target: %s, base rank: %ld, learned rank: 0\n", word.UTF8String, (long)baseRank);
        }
        printf("%d learning checks, %d failures\n", checks, failures);
        return failures ? 1 : 0;
    }
}

static void TestCandidateNavigation(void) {
    Composition *c = NewComposition();
    if (!c) return;
    NSMutableArray *commits = [NSMutableArray array];
    c.committed = ^(NSString *text) { [commits addObject:text]; };
    Type(c, @"shi");
    CandidatePage *first = c.engine.candidatePage;
    Check(first.candidates.count == 15 && first.index == 0 && first.highlighted == 0 && first.hasNextPage && !first.hasPreviousPage, @"The engine provides fifteen candidates with correct page boundaries");
    Check(!c.candidatesExpanded, @"New pinyin starts with a compact candidate row");
    [c handleKey:123 text:@"\uf702" modifiers:0];
    Check(c.engine.highlighted == 0 && c.engine.caret == 3 && [c.engine.rawInput isEqual:@"shi"], @"Compact Left at the first candidate preserves the spelling caret");
    [c handleKey:124 text:@"\uf703" modifiers:0];
    Check(c.engine.highlighted == 1 && c.engine.caret == 3 && !c.candidatesExpanded && !commits.count, @"Compact Right moves the candidate highlight without editing or committing text");
    NSString *selected = c.engine.candidates[c.engine.highlighted];
    [c handleKey:49 text:@" " modifiers:0];
    Check([c.chinese isEqual:selected] && !c.engine.preedit.length && !commits.count, @"Space confirms the visible highlight into the draft only");
    [c cancel]; Type(c, @"shi");
    [c handleKey:28 text:@"8" modifiers:0];
    Check(!c.chinese.length && [c.engine.rawInput isEqual:@"shi"], @"Compact mode cannot select a hidden numbered candidate");
    [c handleKey:125 text:@"\uf701" modifiers:0];
    Check(c.candidatesExpanded && c.engine.candidatePage.index == 0 && c.engine.highlighted == 0, @"First Down expands the candidate grid without skipping to another page");
    [c handleKey:124 text:@"\uf703" modifiers:0];
    [c handleKey:125 text:@"\uf701" modifiers:0];
    Check(c.engine.highlighted == 6, @"Down moves one grid row while preserving the column");
    [c handleKey:125 text:@"\uf701" modifiers:0];
    Check(c.engine.highlighted == 11, @"Repeated Down moves to the bottom row");
    [c handleKey:125 text:@"\uf701" modifiers:0];
    Check(c.engine.candidatePage.index == 1 && c.engine.highlighted == 1, @"Down beyond the bottom automatically opens the next page in the same column");
    [c handleKey:126 text:@"\uf700" modifiers:0];
    Check(c.engine.candidatePage.index == 0 && c.engine.highlighted == 11, @"Up beyond the top returns to the preceding page's bottom row");
    for (int i = 0; i < 4; i++) [c handleKey:124 text:@"\uf703" modifiers:0];
    Check(c.engine.candidatePage.index == 1 && c.engine.highlighted == 0, @"Repeated next-candidate movement crosses pages without skipping words");
    [c handleKey:123 text:@"\uf702" modifiers:0];
    Check(c.engine.candidatePage.index == 0 && c.engine.highlighted == 14, @"Left across a page boundary reaches the preceding last candidate");
    [c handleKey:53 text:@"" modifiers:0];
    Check(!c.candidatesExpanded && c.engine.highlighted < 5 && [c.engine.rawInput isEqual:@"shi"], @"Escape collapses the grid while preserving pinyin and a visible highlight");
    [c handleKey:53 text:@"" modifiers:0];
    Check(!c.hasComposition, @"A further Escape retains the established pinyin cancellation behavior");

    Type(c, @"shi");
    [c handleKey:121 text:@"\uf72d" modifiers:0];
    Check(c.candidatesExpanded && c.engine.candidatePage.index == 0, @"First Page Down expands rather than skipping candidates");
    [c handleKey:121 text:@"\uf72d" modifiers:0];
    Check(c.engine.candidatePage.index == 1 && c.engine.highlighted == 0, @"Further Page Down changes the whole page");
    [c handleKey:124 text:@"\uf703" modifiers:0];
    selected = c.engine.candidates[c.engine.highlighted];
    [c handleKey:49 text:@" " modifiers:0];
    Check([c.chinese isEqual:selected] && !commits.count, @"Space confirms the displayed highlight on a later page");
    [c cancel]; Type(c, @"shi"); [c expandCandidates];
    selected = c.engine.candidates[8];
    [c handleKey:25 text:@"9" modifiers:0];
    Check([c.chinese isEqual:selected] && !c.candidatesExpanded, @"Expanded numbers 1-9 select their displayed candidates and close the grid");
    [c cancel]; Type(c, @"shi"); [c expandCandidates]; [c changeCandidatePage:NO];
    selected = c.engine.candidates[6];
    [c chooseCandidate:6];
    Check([c.chinese isEqual:selected], @"Mouse selection uses the current grid page's candidate index");
    [c cancel]; Type(c, @"shi");
    for (int i = 0; i < 5; i++) [c handleKey:124 text:@"\uf703" modifiers:0];
    Check(c.candidatesExpanded && c.engine.highlighted == 5 && c.engine.caret == 3, @"Right beyond the compact row reveals the next candidate without moving the spelling caret");
    [c expandCandidates];
    int pages = 0;
    while (c.engine.candidatePage.hasNextPage && pages++ < 500) [c changeCandidatePage:NO];
    CandidatePage *last = c.engine.candidatePage;
    Check(!last.hasNextPage && last.index > 0 && last.candidates.count > 0, @"Pagination reaches the actual last page");
    [c.engine moveHighlight:(NSInteger)last.candidates.count - 1 - c.engine.highlighted];
    [c handleKey:125 text:@"\uf701" modifiers:0];
    [c handleKey:124 text:@"\uf703" modifiers:0];
    Check(c.engine.candidatePage.index == last.index && c.engine.highlighted == (NSInteger)last.candidates.count - 1, @"Last-page navigation stays on a valid candidate without wrapping");
    [c handleKey:116 text:@"\uf72c" modifiers:0];
    Check(c.engine.candidatePage.index == last.index - 1 && c.engine.highlighted == 0, @"Page Up changes pages and selects the first item");
    Check(!commits.count && !c.chinese.length, @"Browsing and expanding candidates never submits text");
    [c handleKey:51 text:@"" modifiers:0];
    Check(!c.candidatesExpanded && [c.engine.rawInput isEqual:@"sh"], @"Editing pinyin returns to compact candidates");
    [c cancel];
    Type(c, @"nihao"); Confirm(c); Type(c, @"shi"); [c expandCandidates];
    [c handleKey:53 text:@"" modifiers:0];
    Check([c.chinese isEqual:@"你好"] && [c.engine.rawInput isEqual:@"shi"], @"Collapsing preserves both confirmed Chinese and pending pinyin");
    [c cancel];
    for (NSNumber *setting in @[@3, @7, @9]) {
        c.candidateColumns = setting.integerValue;
        Type(c, @"shi"); [c expandCandidates];
        [c handleKey:124 text:@"\uf703" modifiers:0];
        [c handleKey:125 text:@"\uf701" modifiers:0];
        Check(c.engine.highlighted == 1 + setting.integerValue, @"Grid navigation follows the configured number of columns");
        [c changeCandidatePage:NO];
        [c handleKey:126 text:@"\uf700" modifiers:0];
        Check(c.engine.candidatePage.index == 0 && c.engine.highlighted == (14 / setting.integerValue) * setting.integerValue, @"Cross-page navigation uses the configured row geometry");
        [c collapseCandidates];
        Check(c.engine.highlighted < setting.integerValue && c.engine.preedit.length, @"Collapsed highlight stays within the configured visible row");
        [c cancel];
    }
    c.candidateColumns = 0;
    Check(c.candidateColumns == 5, @"Invalid column count falls back to five");
}

static void TestArrowOwnership(void) {
    Composition *c = NewComposition();
    if (!c) return;
    SentenceView *view = BindSentenceView(c, 420);
    __block NSUInteger commits = 0;
    c.committed = ^(NSString *text) { commits++; };
    Type(c, @"nihaoshijie"); Confirm(c);
    [c handleKey:123 text:@"" modifiers:0]; [c handleKey:123 text:@"" modifiers:0];
    Type(c, @"shi");
    NSString *sentence = c.chinese;
    NSString *marked = c.markedText;
    NSUInteger sentenceCaret = c.chineseCaret, spellingCaret = c.engine.caret, markedCaret = c.markedCaret;
    Check(!view.showsCaret, @"The sentence preview hides its caret while candidates own the arrows");
    for (NSNumber *key in @[@124, @125, @125, @126, @123]) {
        Check([c handleKey:key.unsignedIntegerValue text:@"" modifiers:0] &&
            [c.chinese isEqual:sentence] && [c.markedText isEqual:marked] &&
            c.chineseCaret == sentenceCaret && c.engine.caret == spellingCaret && c.markedCaret == markedCaret,
            @"Candidate arrows keep both the confirmed sentence and pending-spelling caret fixed");
    }
    [c handleKey:0 text:@"a" modifiers:NSEventModifierFlagCommand];
    [c handleKey:123 text:@"" modifiers:0];
    Check(!c.markedSelection.length && c.chineseCaret == sentenceCaret && c.engine.caret == spellingCaret && ![c.hint isEqual:L(@"Draft selected · ⌘C copy · ⌘X cut · ⌘V replace · ⌘Z undo")], @"Arrows after Select All return to candidates without moving the sentence caret");
    NSString *chosen = c.engine.candidates[c.engine.highlighted];
    Confirm(c);
    Check(!c.engine.preedit.length && [c.chinese isEqual:[sentence stringByReplacingCharactersInRange:NSMakeRange(sentenceCaret, 0) withString:chosen]], @"Selection inserts at the preserved middle position");
    Check(view.showsCaret, @"Finishing selection restores the visible sentence caret");
    NSUInteger confirmedCaret = c.chineseCaret;
    [c handleKey:123 text:@"" modifiers:0];
    Check(c.chineseCaret < confirmedCaret && !c.engine.preedit.length, @"Left immediately edits the sentence after all candidates are confirmed");
    [c handleKey:124 text:@"" modifiers:0];
    Check(c.chineseCaret == confirmedCaret && commits == 0, @"Right returns the sentence caret without committing text");
    [c handleKey:6 text:@"z" modifiers:NSEventModifierFlagCommand];
    Check([c.engine.rawInput isEqual:@"shi"] && [c.chinese isEqual:sentence], @"Undoing selection restores a pending candidate stage");
    spellingCaret = c.engine.caret;
    [c handleKey:124 text:@"" modifiers:0];
    Check(c.engine.highlighted == 1 && c.engine.caret == spellingCaret && c.chineseCaret == sentenceCaret, @"Restored candidates automatically regain arrow ownership");
    [c cancel];

    Type(c, @"womenmingtian");
    NSUInteger index = FindCandidate(c, @"我们");
    Check(index != NSNotFound, @"The partial-selection arrow fixture finds 我们");
    if (index != NSNotFound) {
        [c chooseCandidate:index];
        Check(c.engine.preedit.length > 0, @"Selecting a prefix leaves the remaining candidates active");
        spellingCaret = c.engine.caret;
        sentenceCaret = c.chineseCaret;
        [c handleKey:124 text:@"" modifiers:0];
        Check(c.engine.highlighted == 1 && c.engine.caret == spellingCaret && c.chineseCaret == sentenceCaret, @"A partially confirmed phrase keeps arrow keys in the remaining candidates");
        Confirm(c);
        Check(!c.engine.preedit.length && [c.chinese hasPrefix:@"我们"] && view.showsCaret, @"The sentence caret resumes only after the whole phrase is selected");
    }
    Check(commits == 0, @"Candidate navigation and cursor handoff never commit to the host");
    [c cancel];
}

@interface Composition (EditingTests)
- (void)appendLiteral:(NSString *)text;
@end

static NSArray *SentenceGlyphPositions(SentenceView *view) {
    NSLayoutManager *manager = view.textView.layoutManager;
    [manager ensureLayoutForTextContainer:view.textView.textContainer];
    NSMutableArray *positions = [NSMutableArray array];
    for (NSUInteger i = 0; i < manager.numberOfGlyphs; i++) {
        [positions addObject:[NSValue valueWithPoint:[manager locationForGlyphAtIndex:i]]];
        [positions addObject:[NSValue valueWithRect:[manager lineFragmentRectForGlyphAtIndex:i effectiveRange:NULL]]];
    }
    return positions;
}

static void TestSentenceNavigation(void) {
    Composition *c = NewComposition();
    SentenceView *view = BindSentenceView(c, 420);
    __block NSUInteger translations = 0, commits = 0;
    c.service = ^(NSString *text, TranslationCompletion done) { translations++; done(@"Translation", nil); };
    c.committed = ^(NSString *text) { commits++; };
    c.pasteText = ^{ return @"一二三四五六七八九十\n一\n一二三四五六七八九十"; };
    Type(c, @"ni");
    [c handleKey:0 text:@"a" modifiers:NSEventModifierFlagCommand];
    [c handleKey:9 text:@"v" modifiers:NSEventModifierFlagCommand];
    [c handleKey:115 text:@"" modifiers:0];
    for (int i = 0; i < 8; i++) [c handleKey:124 text:@"" modifiers:0];
    Pump(0.5);
    Check(c.ready && translations == 1 && c.chineseCaret == 8, @"Multiline paste is ready for sentence navigation");
    CGFloat originalX = view.caretRect.origin.x;
    [c handleKey:125 text:@"" modifiers:0];
    Check(c.chineseCaret == 12, @"Down clamps to the end of a short next line");
    [c handleKey:125 text:@"" modifiers:0];
    Check(c.chineseCaret == 21 && fabs(view.caretRect.origin.x - originalX) < 1, @"Down restores the preferred column after a short line");
    [c handleKey:126 text:@"" modifiers:0]; [c handleKey:126 text:@"" modifiers:0];
    Check(c.chineseCaret == 8, @"Up returns through the short line to the original column");
    [c handleKey:125 text:@"" modifiers:0]; [c handleKey:123 text:@"" modifiers:0];
    [c handleKey:126 text:@"" modifiers:0];
    Check(c.chineseCaret == 0, @"Horizontal movement resets the preferred vertical column");
    [c handleKey:126 text:@"" modifiers:0];
    Check(c.chineseCaret == 0, @"Up at the beginning stays inside the sentence");
    [c handleKey:119 text:@"" modifiers:0]; [c handleKey:125 text:@"" modifiers:0];
    Check(c.chineseCaret == c.chinese.length, @"Down at the end stays inside the sentence");
    Pump(0.4);
    Check(translations == 1 && c.ready && !commits, @"Caret navigation preserves the ready translation without another request or host commit");
    [c handleKey:0 text:@"a" modifiers:NSEventModifierFlagCommand];
    Check(!view.showsCaret && view.selectionRange.length == c.chinese.length, @"Select All highlights real text and hides the overlay caret");
    [c handleKey:126 text:@"" modifiers:0];
    Check(view.showsCaret && !c.markedSelection.length && c.chineseCaret < c.chinese.length, @"Up after Select All resumes sentence editing");
    NSString *beforeEdit = c.chinese;
    NSUInteger beforeCaret = c.chineseCaret;
    [c handleKey:51 text:@"" modifiers:0];
    [c handleKey:6 text:@"z" modifiers:NSEventModifierFlagCommand];
    Check([c.chinese isEqual:beforeEdit] && c.chineseCaret == beforeCaret, @"Undo after a vertical move restores the sentence and its caret");

    [c cancel];
    view = BindSentenceView(c, 260);
    Type(c, @"ni");
    c.pasteText = ^{ return @"我们明天下午开会讨论新的设计方案，我们明天下午开会讨论新的设计方案，我们明天下午开会讨论新的设计方案，我们明天下午开会讨论新的设计方案。"; };
    [c handleKey:0 text:@"a" modifiers:NSEventModifierFlagCommand];
    [c handleKey:9 text:@"v" modifiers:NSEventModifierFlagCommand];
    Check(view.textView.frame.size.height > view.frame.size.height && [view.textView.string isEqual:c.chinese], @"Long sentences retain all text in a bounded scrolling viewport");
    [c handleKey:115 text:@"" modifiers:0];
    for (int i = 0; i < 5; i++) [c handleKey:124 text:@"" modifiers:0];
    NSRect first = view.caretRect;
    [c handleKey:125 text:@"" modifiers:0];
    Check(c.chineseCaret > 5 && view.caretRect.origin.y > first.origin.y && fabs(view.caretRect.origin.x - first.origin.x) < 1,
        @"Down navigates a soft-wrapped line without requiring a newline");
    [c handleKey:126 text:@"" modifiers:0];
    Check(c.chineseCaret == 5 && NSEqualRects(view.caretRect, first), @"Up reverses a soft-wrap movement");
    for (int i = 0; i < 5; i++) [c handleKey:125 text:@"" modifiers:0];
    Check(NSContainsRect(view.textView.visibleRect, view.caretRect), @"The scrolling viewport follows the sentence caret");
    Check(!view.textView.acceptsFirstResponder && [view.textView hitTest:NSMakePoint(5, 5)] == nil, @"Sentence rendering never takes input focus from the host");
    NSArray *wrappedPositions = SentenceGlyphPositions(view);
    BOOL stableWrapping = YES;
    [c handleKey:115 text:@"" modifiers:0];
    for (NSUInteger i = 0; i <= c.chinese.length; i++) {
        stableWrapping &= [SentenceGlyphPositions(view) isEqual:wrappedPositions];
        [c handleKey:124 text:@"" modifiers:0];
    }
    Check(stableWrapping, @"Caret movement at every soft-wrap boundary preserves all glyph and line positions");

    [c cancel];
    view = BindSentenceView(c, 420);
    Type(c, @"ni");
    c.pasteText = ^{ return @"中文 hello 👨‍👩‍👧‍👦 e\u0301。"; };
    [c handleKey:0 text:@"a" modifiers:NSEventModifierFlagCommand];
    [c handleKey:9 text:@"v" modifiers:NSEventModifierFlagCommand];
    NSString *text = c.chinese;
    NSArray *positions = SentenceGlyphPositions(view);
    CGFloat height = view.intrinsicContentSize.height;
    BOOL stable = YES, boundaries = YES;
    [c handleKey:115 text:@"" modifiers:0];
    do {
        stable &= [view.textView.string isEqual:text] && [SentenceGlyphPositions(view) isEqual:positions] && view.intrinsicContentSize.height == height;
        boundaries &= c.chineseCaret == text.length || [text rangeOfComposedCharacterSequenceAtIndex:c.chineseCaret].location == c.chineseCaret;
        if (c.chineseCaret == text.length) break;
        [c handleKey:124 text:@"" modifiers:0];
    } while (YES);
    Check(stable && ![view.textView.string containsString:@"│"], @"Moving the overlay caret never adds a glyph, shifts text, or changes wrapping");
    Check(boundaries, @"Caret positions preserve emoji families and combining characters");
    Type(c, @"shi");
    Check(!view.showsCaret, @"Starting candidates hides the sentence overlay caret");
    NSUInteger fixed = c.chineseCaret;
    [c handleKey:125 text:@"" modifiers:0]; [c handleKey:126 text:@"" modifiers:0];
    Check(c.chineseCaret == fixed && !view.showsCaret, @"Pending pinyin retains vertical arrow ownership");
    [c handleKey:36 text:@"" modifiers:0];
    Check(view.showsCaret && [c.chinese hasSuffix:@"shi"], @"Confirming literal English restores the sentence caret");

    [c cancel]; Type(c, @"ni");
    c.pasteText = ^{ return @"中\n\n英文\n"; };
    [c handleKey:0 text:@"a" modifiers:NSEventModifierFlagCommand];
    [c handleKey:9 text:@"v" modifiers:NSEventModifierFlagCommand];
    Check(view.caretRect.size.height > 0 && NSContainsRect(view.textView.visibleRect, view.caretRect), @"A trailing newline has a visible caret on its empty final line");
    [c handleKey:115 text:@"" modifiers:0];
    [c handleKey:125 text:@"" modifiers:0];
    Check(c.chineseCaret == 2, @"Down can enter an empty middle line");
    [c handleKey:125 text:@"" modifiers:0];
    Check(c.chineseCaret == 3, @"Down continues past an empty line");
    [c handleKey:0 text:@"a" modifiers:NSEventModifierFlagCommand];
    [c handleKey:51 text:@"" modifiers:0];
    Check(!view.textView.string.length && view.showsCaret && view.caretRect.size.height > 0 && view.intrinsicContentSize.height < 40,
        @"Deleting all text leaves a visible zero-width caret in a single-line editing session");
    [c handleKey:6 text:@"z" modifiers:NSEventModifierFlagCommand];
    Check([view.textView.string isEqual:@"中\n\n英文\n"], @"Undo restores multiline text after clearing the viewport");

    c.pasteText = ^{ return @"ab👨‍👩‍👧‍👦cd\n你e\u0301字\nuvwxyz"; };
    [c handleKey:0 text:@"a" modifiers:NSEventModifierFlagCommand];
    [c handleKey:9 text:@"v" modifiers:NSEventModifierFlagCommand];
    BOOL verticalBoundaries = YES;
    NSString *unicode = c.chinese;
    for (NSUInteger i = 0; i <= unicode.length; i++) {
        if (i < unicode.length && [unicode rangeOfComposedCharacterSequenceAtIndex:i].location != i) continue;
        [c handleKey:115 text:@"" modifiers:0];
        while (c.chineseCaret < i) [c handleKey:124 text:@"" modifiers:0];
        for (NSNumber *key in @[@125, @126]) {
            [c handleKey:key.unsignedIntegerValue text:@"" modifiers:0];
            verticalBoundaries &= c.chineseCaret == unicode.length || [unicode rangeOfComposedCharacterSequenceAtIndex:c.chineseCaret].location == c.chineseCaret;
        }
    }
    Check(verticalBoundaries && [c.chinese isEqual:unicode], @"Vertical navigation never lands inside an emoji family or combining sequence");
    Check(!commits, @"Sentence layout and editing never commit implicitly");
    [c cancel];
}

static void TestTextEditing(void) {
    Composition *c = NewComposition();
    NSMutableArray *commits = [NSMutableArray array];
    NSMutableArray *responses = [NSMutableArray array];
    NSMutableArray *sources = [NSMutableArray array];
    c.committed = ^(NSString *text) { [commits addObject:text]; };
    c.service = ^(NSString *text, TranslationCompletion completion) {
        [sources addObject:text]; [responses addObject:[completion copy]];
    };
    Type(c, @"nihaoshijie"); Confirm(c); Pump(0.4);
    Check([c.chinese isEqual:@"你好世界"] && c.chineseCaret == 4, @"Confirmed text starts with the caret at its end");
    [c handleKey:123 text:@"" modifiers:0]; [c handleKey:123 text:@"" modifiers:0];
    Check(c.chineseCaret == 2 && c.markedCaret == 2 && [c.markedText isEqual:@"你好世界"], @"Moving within confirmed Chinese changes the caret without changing the marked text");
    Pump(0.4);
    Check(sources.count == 1 && !commits.count, @"Caret movement neither translates again nor commits to the host");
    Type(c, @"zhongguo");
    Check([c.markedText hasPrefix:@"你好"] && [c.markedText hasSuffix:@"世界"] && c.markedCaret < c.markedText.length, @"Pending pinyin is shown at the insertion point, preserving the suffix");
    Confirm(c);
    Check([c.chinese isEqual:@"你好中国世界"] && c.chineseCaret == 4, @"A selected word inserts into the middle of the sentence");
    [c handleKey:51 text:@"" modifiers:0];
    Check([c.chinese isEqual:@"你好中世界"] && c.chineseCaret == 3, @"Backspace removes the character before the caret");
    [c handleKey:117 text:@"" modifiers:0];
    Check([c.chinese isEqual:@"你好中界"] && c.chineseCaret == 3, @"Forward Delete removes the character after the caret");
    [c handleKey:43 text:@"," modifiers:0];
    Check([c.chinese isEqual:@"你好中，界"] && c.chineseCaret == 4, @"Punctuation also inserts at the caret");
    if (responses.count) { TranslationCompletion old = responses[0]; old(@"STALE", nil); Pump(0.03); }
    Check(!c.ready && !c.english.length, @"A middle edit invalidates the previous sentence translation");
    Pump(0.4);
    Check([sources.lastObject isEqual:c.chinese], @"Translation receives the full edited sentence including the suffix");
    TranslationCompletion latest = responses.lastObject; latest(@"Edited sentence", nil); Pump(0.03);
    [c handleKey:123 text:@"" modifiers:0];
    Check(c.ready && [c.english isEqual:@"Edited sentence"], @"Moving the caret preserves a valid translation");
    [c commitChinese];
    Check([commits.lastObject isEqual:@"你好中，界"] && !c.hasComposition && c.chineseCaret == 0, @"Chinese commit includes both sides of the caret exactly once");

    Type(c, @"nihao");
    // Exercise the engine's editing positions independently of candidate arrow keys.
    c.engine.caret = 2;
    Check(c.engine.caret == 2 && c.markedCaret <= c.markedText.length, @"An explicit engine caret remains valid within pending spelling");
    Type(c, @"m");
    Check([c.engine.rawInput isEqual:@"nimhao"] && c.engine.caret == 3, @"Typing inserts into the middle of pending pinyin");
    [c handleKey:51 text:@"" modifiers:0];
    Check([c.engine.rawInput isEqual:@"nihao"] && c.engine.caret == 2, @"Backspace edits pending pinyin at its caret");
    [c handleKey:117 text:@"" modifiers:0];
    Check([c.engine.rawInput isEqual:@"niao"] && c.engine.caret == 2, @"Forward Delete edits pending pinyin at its caret");
    [c handleKey:115 text:@"" modifiers:0];
    [c handleKey:51 text:@"" modifiers:0];
    Check(c.engine.caret == 0 && [c.engine.rawInput isEqual:@"niao"], @"Backspace at the beginning of pinyin preserves the spelling");
    [c handleKey:119 text:@"" modifiers:0];
    [c handleKey:117 text:@"" modifiers:0];
    Check(c.engine.caret == 4 && [c.engine.rawInput isEqual:@"niao"], @"Forward Delete at the end of pinyin preserves the spelling");
    [c expandCandidates]; NSUInteger caret = c.engine.caret;
    [c handleKey:124 text:@"" modifiers:0];
    Check(c.engine.caret == caret && c.engine.highlighted == 1, @"Expanded arrows choose candidates without moving the text caret");
    [c handleKey:53 text:@"" modifiers:0]; [c handleKey:123 text:@"" modifiers:0];
    Check(!c.candidatesExpanded && c.engine.caret == caret && c.engine.highlighted == 0, @"Collapsed candidates retain arrow ownership until spelling is confirmed");
    [c cancel];

    Type(c, @"nihao"); Confirm(c);
    [c handleKey:115 text:@"" modifiers:0]; [c handleKey:51 text:@"" modifiers:0];
    Check(c.chineseCaret == 0 && [c.chinese isEqual:@"你好"], @"Home and Backspace respect the confirmed sentence boundary");
    [c handleKey:119 text:@"" modifiers:0]; [c handleKey:117 text:@"" modifiers:0];
    Check(c.chineseCaret == 2 && [c.chinese isEqual:@"你好"], @"End and Forward Delete respect the confirmed sentence boundary");
    [c handleKey:123 text:@"" modifiers:0]; Type(c, @"abc");
    [c handleKey:36 text:@"\r" modifiers:0];
    Check([c.chinese isEqual:@"你abc好"] && commits.count == 1, @"Return inserts raw spelling at its actual sentence insertion point");
    [c commitChinese];
    Check([commits.lastObject isEqual:@"你abc好"] && !c.inputEnglish && !c.directEnglish, @"Explicit commit preserves the keyboard language after middle insertion");
    Type(c, @"ni"); Confirm(c);
    [c appendLiteral:@"👨‍👩‍👧‍👦e\u0301"];
    [c handleKey:123 text:@"" modifiers:0]; [c handleKey:51 text:@"" modifiers:0];
    Check([c.chinese isEqual:@"你e\u0301"] && c.chineseCaret == 1, @"Cursor movement and deletion preserve complete emoji and combining character sequences");
    [c handleKey:117 text:@"" modifiers:0];
    Check([c.chinese isEqual:@"你"] && commits.count == 2, @"Forward deletion removes a whole combining character without committing");
    [c cancel];
}

static void CollectCandidateButtons(NSView *view, NSMutableArray<NSButton *> *buttons) {
    if ([view isKindOfClass:NSClassFromString(@"CandidateChoiceButton")]) [buttons addObject:(NSButton *)view];
    for (NSView *child in view.subviews) CollectCandidateButtons(child, buttons);
}

static void TestCandidateLayout(void) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1000, 700) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    CandidateListView *view = [[CandidateListView alloc] initWithFrame:NSZeroRect];
    window.contentView = view;
    NSArray *words = @[@"是", @"时候", @"事情", @"使用", @"市", @"试试看", @"世界", @"实际上", @"时间", @"十", @"诗", @"石头", @"食物", @"历史", @"世纪"];
    CandidatePage *page = [[CandidatePage alloc] initWithCandidates:words highlighted:0 index:0 hasNextPage:YES];
    [view updateWithPage:page expanded:NO columns:5]; [view layoutSubtreeIfNeeded];
    NSMutableArray<NSButton *> *compact = [NSMutableArray array]; CollectCandidateButtons(view, compact);
    CGFloat width = view.contentWidth;
    NSMutableArray *compactWidths = [NSMutableArray array];
    for (NSButton *button in compact) [compactWidths addObject:@(button.frame.size.width)];
    [view updateWithPage:page expanded:YES columns:5]; [view layoutSubtreeIfNeeded];
    NSMutableArray<NSButton *> *expanded = [NSMutableArray array]; CollectCandidateButtons(view, expanded);
    BOOL same = compact.count == 5 && expanded.count == 15 && width == view.contentWidth;
    for (NSUInteger i = 0; i < MIN((NSUInteger)5, expanded.count); i++)
        same = same && fabs(expanded[i].frame.size.width - [compactWidths[i] doubleValue]) < 0.01;
    Check(same, @"Compact and expanded candidates keep identical measured column widths");
    Check(expanded[0].frame.size.width != expanded[1].frame.size.width, @"Columns adapt to their actual candidate text rather than using equal fixed widths");
    NSString *longWord = [@"这是一个需要完整显示的长句候选" stringByPaddingToLength:160 withString:@"这是一个需要完整显示的长句候选" startingAtIndex:0];
    NSMutableArray *longWords = [words mutableCopy]; longWords[0] = longWord;
    page = [[CandidatePage alloc] initWithCandidates:longWords highlighted:0 index:0 hasNextPage:NO];
    view.maximumWidth = 360; view.maximumHeight = 120;
    [view updateWithPage:page expanded:YES columns:5]; [view layoutSubtreeIfNeeded];
    NSMutableArray<NSButton *> *wrapped = [NSMutableArray array]; CollectCandidateButtons(view, wrapped);
    Check(view.contentWidth <= 360 && [wrapped[0].title containsString:longWord] && wrapped[0].frame.size.height > 30, @"Long candidates retain full text and wrap within the available screen width");
    NSScrollView *scroll = (NSScrollView *)view.arrangedSubviews.firstObject;
    Check(scroll.frame.size.height <= 120 && scroll.documentView.frame.size.height > 120, @"Tall candidate pages scroll instead of being clipped off screen");
    [window close];
}

static void TestMixedInput(void) {
    Composition *c = NewComposition();
    NSMutableArray *commits = [NSMutableArray array];
    NSMutableArray *sources = [NSMutableArray array];
    NSMutableArray *responses = [NSMutableArray array];
    c.committed = ^(NSString *text) { [commits addObject:text]; };
    c.service = ^(NSString *text, TranslationCompletion completion) {
        [sources addObject:text]; [responses addObject:[completion copy]];
    };
    NSEventModifierFlags shift = NSEventModifierFlagShift;
    Type(c, @"hello");
    [c handleKey:36 text:@"\r" modifiers:0];
    Check([c.chinese isEqual:@"hello"] && !c.engine.preedit.length && !commits.count && !c.directEnglish, @"Enter confirms pending English spelling into the draft without committing or changing language");
    [c handleKey:49 text:@" " modifiers:0];
    Type(c, @"shijie"); Confirm(c);
    Check([c.chinese isEqual:@"hello 世界"] && !commits.count, @"Literal English, a space and selected Chinese share one sentence");
    [c handleKey:36 text:@"\r" modifiers:0];
    Check([commits isEqual:@[@"hello 世界"]] && !c.hasComposition, @"A later Enter with no pending spelling commits the complete mixed sentence once");

    Type(c, @"nihao"); [c expandCandidates];
    [c handleModifiers:shift];
    Check(c.engine.preedit.length && !c.chinese.length, @"Pressing Shift waits for release to distinguish a tap from a chord");
    Check([c handleModifiers:0] && [c.chinese isEqual:@"nihao"] && !c.engine.preedit.length && !c.candidatesExpanded, @"A Shift tap confirms the raw spelling without display separators and closes candidates");
    [c handleModifiers:0];
    Check([c.chinese isEqual:@"nihao"] && commits.count == 1 && !c.directEnglish, @"Duplicate Shift release events neither duplicate text nor switch language");
    [c cancel]; Type(c, @"xi'an");
    [c handleKey:76 text:@"\r" modifiers:0];
    Check([c.chinese isEqual:@"xian"], @"Keypad Enter removes explicitly typed pinyin separators too");
    [c cancel];

    Type(c, @"nihao"); Confirm(c); Pump(0.4);
    [c handleKey:123 text:@"" modifiers:0];
    Type(c, @"hello"); [c handleModifiers:shift]; [c handleModifiers:0];
    Check([c.chinese isEqual:@"你hello好"] && c.chineseCaret == 6, @"Shift-confirmed English inserts at the middle caret, preserving both sides");
    if (responses.count) { TranslationCompletion old = responses.lastObject; old(@"STALE", nil); Pump(0.03); }
    Check(!c.ready && !c.english.length, @"Literal confirmation invalidates a previous translation");
    Pump(0.4);
    Check([sources.lastObject isEqual:@"你hello好"], @"Translation receives the complete mixed sentence after literal confirmation");
    [c cancel];

    Type(c, @"hello"); [c handleModifiers:shift];
    [c handleKey:0 text:@"W" modifiers:shift];
    [c handleKey:0 text:@"O" modifiers:shift];
    [c handleModifiers:0];
    Check([c.chinese isEqual:@"helloWO"] && !c.engine.preedit.length && commits.count == 1, @"Shift-letter chords preserve raw spelling and append uppercase letters without a second confirmation on release");
    Type(c, @"shijie"); Confirm(c);
    Check([c.chinese isEqual:@"helloWO世界"] && !c.directEnglish, @"Chinese entry resumes immediately after a Shift-letter chord");
    [c cancel];

    Type(c, @"hello"); [c handleModifiers:shift];
    [c handleKey:51 text:@"" modifiers:shift]; [c handleModifiers:0];
    Check([c.engine.rawInput isEqual:@"hell"] && !c.chinese.length, @"Shift with Backspace edits spelling without triggering tap confirmation");
    [c cancel]; Type(c, @"hello"); [c handleModifiers:shift];
    [c handleKey:8 text:@"c" modifiers:shift | NSEventModifierFlagCommand]; [c handleModifiers:0];
    Check([c.engine.rawInput isEqual:@"hello"] && commits.count == 1, @"Shift with Command preserves spelling without triggering literal confirmation");
    [c cancel];
    Type(c, @"hello"); [c handleModifiers:shift]; [c cancel]; [c handleModifiers:0];
    Check(!c.hasComposition && commits.count == 1, @"Cancelling while Shift is held prevents insertion on release");
    Type(c, @"hello"); [c synchronizeModifiers:shift]; [c handleModifiers:0];
    Check([c.engine.rawInput isEqual:@"hello"] && !c.chinese.length, @"Focus synchronization does not create a phantom Shift tap");
    [c cancel]; c.directEnglish = YES;
    [c handleModifiers:shift | NSEventModifierFlagCapsLock]; [c handleModifiers:NSEventModifierFlagCapsLock];
    Check(c.directEnglish && !c.hasComposition && commits.count == 1, @"Shift alone in direct English mode keeps its established behavior");
    c.directEnglish = NO;
    Type(c, @"womenmingtian");
    NSUInteger prefix = [c.engine.candidates indexOfObject:@"我们"];
    Check(prefix != NSNotFound, @"The dictionary offers a shorter prefix for partial selection");
    if (prefix != NSNotFound) {
        [c chooseCandidate:prefix];
        [c handleKey:36 text:@"\r" modifiers:0];
        Check([c.chinese isEqual:@"我们mingtian"], @"Literal confirmation preserves Chinese already selected within a multi-segment spelling");
    }
    [c cancel];
}

static void TestShiftAndPunctuation(void) {
    Composition *c = NewComposition();
    if (!c) return;
    NSMutableArray *commits = [NSMutableArray array];
    NSMutableArray *sources = [NSMutableArray array];
    NSMutableArray *responses = [NSMutableArray array];
    c.committed = ^(NSString *text) { [commits addObject:text]; };
    c.service = ^(NSString *text, TranslationCompletion completion) {
        [sources addObject:text]; [responses addObject:[completion copy]];
    };
    NSEventModifierFlags shift = NSEventModifierFlagShift;
    [c handleModifiers:shift]; [c handleModifiers:0];
    Check(!c.directEnglish && !c.hasComposition && !commits.count, @"Tapping Shift does not change language or insert text");
    for (NSString *letter in @[@"A", @"P", @"I"]) [c handleKey:0 text:letter modifiers:shift];
    Check([[commits componentsJoinedByString:@""] isEqual:@"API"] && !c.directEnglish && !c.hasComposition, @"Shift letters insert uppercase English in idle Chinese mode");
    [c handleKey:18 text:@"!" modifiers:shift];
    [c handleKey:44 text:@"?" modifiers:shift];
    [c handleKey:41 text:@":" modifiers:shift];
    [c handleKey:29 text:@"(" modifiers:shift];
    [c handleKey:25 text:@")" modifiers:shift];
    [c handleKey:43 text:@"," modifiers:0];
    [c handleKey:47 text:@"." modifiers:0];
    Check([[commits componentsJoinedByString:@""] isEqual:@"API！？：（），。"], @"Chinese punctuation follows language, with and without Shift, even without a draft");
    Pump(0.4);
    Check(!sources.count, @"Standalone Shift English and punctuation need no translation");
    Type(c, @"nihao");
    NSUInteger commitCount = commits.count;
    [c handleKey:0 text:@"A" modifiers:shift];
    Check([c.chinese isEqual:@"nihaoA"] && !c.engine.preedit.length && commits.count == commitCount, @"Shift letter preserves pending raw spelling and adds uppercase English to the draft");
    [c handleModifiers:0]; [c cancel]; Type(c, @"nihao");
    Confirm(c); Pump(0.5);
    Check([c.chinese isEqual:@"你好"], @"Releasing Shift resumes normal pinyin selection");
    for (NSString *letter in @[@"A", @"P", @"I"]) [c handleKey:0 text:letter modifiers:shift];
    [c handleKey:18 text:@"!" modifiers:shift];
    Check([c.chinese isEqual:@"你好API！"] && commits.count == commitCount && !c.directEnglish, @"Temporary English and Chinese punctuation stay in the same uncommitted sentence");
    if (responses.count) { TranslationCompletion old = responses[0]; old(@"STALE", nil); Pump(0.03); }
    Check(!c.ready && !c.english.length, @"Adding temporary English invalidates an older sentence translation");
    Pump(0.5);
    Check([sources.lastObject isEqual:@"你好API！"], @"Translation receives the entire mixed sentence after the edit");
    Type(c, @"hao"); Confirm(c);
    Check([c.chinese isEqual:@"你好API！好"], @"Chinese input resumes immediately after Shift is released");
    [c commitChinese];
    Check([commits.lastObject isEqual:@"你好API！好"] && commits.count == commitCount + 1, @"Mixed sentence commits once only when explicitly confirmed");

    [c handleKey:39 text:@"\"" modifiers:shift];
    [c handleKey:39 text:@"\"" modifiers:shift];
    Check([commits[commits.count - 2] isEqual:@"“"] && [commits.lastObject isEqual:@"”"], @"Chinese double quotes alternate opening and closing");
    Type(c, @"ni"); Confirm(c);
    [c handleKey:39 text:@"\"" modifiers:shift];
    [c cancel];
    [c handleKey:39 text:@"\"" modifiers:shift];
    Check([commits.lastObject isEqual:@"“"], @"Cancelling a draft also restores its quote-pair state");
    [c handleKey:39 text:@"\"" modifiers:shift];

    c.directEnglish = YES;
    commitCount = commits.count;
    for (NSString *symbol in @[@"!", @"?", @":", @"(", @")", @"\"", @"<", @">", @"^", @"_"])
        [c handleKey:18 text:symbol modifiers:shift | NSEventModifierFlagCapsLock];
    NSString *englishPunctuation = [[commits subarrayWithRange:NSMakeRange(commitCount, commits.count - commitCount)] componentsJoinedByString:@""];
    Check([englishPunctuation isEqual:@"!?:()\"<>^_"] && c.directEnglish, @"Shift symbols stay ASCII in English mode");
    c.directEnglish = NO;
    Type(c, @"nihao"); Confirm(c);
    commitCount = commits.count;
    Check([c handleKey:123 text:@"\uf702" modifiers:shift] && [c.chinese isEqual:@"你好"] && NSEqualRanges(c.markedSelection, NSMakeRange(1, 1)) && commits.count == commitCount, @"Shift selection stays inside the confirmed sentence without committing");
    [c cancel];
    Type(c, @"nihao"); Confirm(c);
    Check(![c handleKey:48 text:@"\t" modifiers:shift] && !c.hasComposition && commits.count == commitCount, @"Shift Tab preserves host focus navigation instead of committing a translation");
    Check(!c.directEnglish, @"Shift combinations never leave Chinese mode selected as English");
    [c cancel];
}

static void LoadDraft(Composition *c, NSString *text) {
    [c cancel];
    Type(c, @"ni");
    c.pasteText = ^{ return text; };
    [c handleKey:0 text:@"a" modifiers:NSEventModifierFlagCommand];
    [c handleKey:9 text:@"v" modifiers:NSEventModifierFlagCommand];
}

static void SelectWorld(Composition *c) {
    [c handleKey:115 text:@"" modifiers:0];
    [c handleKey:124 text:@"" modifiers:0]; [c handleKey:124 text:@"" modifiers:0];
    [c handleKey:124 text:@"" modifiers:NSEventModifierFlagShift];
    [c handleKey:124 text:@"" modifiers:NSEventModifierFlagShift];
}

static void TestPartialSelection(void) {
    Composition *c = NewComposition();
    SentenceView *view = BindSentenceView(c, 420);
    NSEventModifierFlags shift = NSEventModifierFlagShift, command = NSEventModifierFlagCommand;
    __block NSString *clipboard = @"untouched";
    __block NSUInteger copies = 0, commits = 0;
    c.copyText = ^(NSString *text) { clipboard = text; copies++; };
    c.committed = ^(NSString *text) { commits++; };
    NSMutableArray<TranslationCompletion> *responses = [NSMutableArray array];
    c.service = ^(NSString *text, TranslationCompletion done) { [responses addObject:[done copy]]; };
    NSString *original = @"你好世界欢迎你";
    LoadDraft(c, original);
    Pump(0.4);
    TranslationCompletion previous = responses.lastObject;
    previous(@"Hello world", nil); Pump(0.02);
    SelectWorld(c);
    NSArray *positions = SentenceGlyphPositions(view);
    Check(NSEqualRanges(c.markedSelection, NSMakeRange(2, 2)) && c.chineseCaret == 4, @"Shift Right selects only 世界 in the middle of the sentence");
    Check(NSEqualRanges(view.selectionRange, c.markedSelection) && !view.showsCaret &&
        NSEqualRanges(view.textView.accessibilitySelectedTextRange, c.markedSelection) && [view.textView.accessibilitySelectedText isEqual:@"世界"],
        @"The panel and accessibility expose the exact partial selection without an extra caret");
    [c handleKey:123 text:@"" modifiers:shift];
    Check(NSEqualRanges(c.markedSelection, NSMakeRange(2, 1)) && c.chineseCaret == 3, @"Reversing Shift Left shrinks the selection from its active endpoint");
    [c handleKey:123 text:@"" modifiers:shift];
    Check(!c.markedSelection.length && c.chineseCaret == 2 && view.showsCaret, @"Shrinking to the anchor restores the caret");
    [c handleKey:123 text:@"" modifiers:shift];
    Check(NSEqualRanges(c.markedSelection, NSMakeRange(1, 1)) && c.chineseCaret == 1, @"Shift Left can cross the original anchor");
    for (int i = 0; i < 3; i++) [c handleKey:124 text:@"" modifiers:shift];
    Check(NSEqualRanges(c.markedSelection, NSMakeRange(2, 2)) && [SentenceGlyphPositions(view) isEqual:positions], @"Extending and reversing a selection never shifts the text");
    [c handleKey:8 text:@"c" modifiers:command]; Pump(0.4);
    Check([clipboard isEqual:@"世界"] && copies == 1 && [c.chinese isEqual:original] && c.ready && responses.count == 1, @"Copy exports only the selection and preserves text and translation");
    [c handleKey:7 text:@"x" modifiers:command];
    Check([clipboard isEqual:@"世界"] && [c.chinese isEqual:@"你好欢迎你"] && c.chineseCaret == 2 && !c.markedSelection.length && !c.ready, @"Cut removes only the selected span and leaves the caret at its start");
    previous(@"STALE", nil); Pump(0.02);
    Check(![c.english isEqual:@"STALE"], @"A response for the pre-cut sentence cannot reappear");
    [c handleKey:6 text:@"z" modifiers:command];
    Check([c.chinese isEqual:original] && NSEqualRanges(c.markedSelection, NSMakeRange(2, 2)) && c.chineseCaret == 4, @"Undo restores both partial selection endpoints after cut");
    [c handleKey:123 text:@"" modifiers:shift];
    Check(NSEqualRanges(c.markedSelection, NSMakeRange(2, 1)), @"Undo preserves selection direction for subsequent Shift arrows");
    [c handleKey:124 text:@"" modifiers:shift];
    [c handleKey:6 text:@"Z" modifiers:command | shift];
    Check([c.chinese isEqual:@"你好欢迎你"] && !c.markedSelection.length, @"Redo restores the cut after selection-only navigation");

    for (NSNumber *key in @[@51, @117]) {
        LoadDraft(c, original); SelectWorld(c);
        [c handleKey:key.unsignedIntegerValue text:@"" modifiers:0];
        Check([c.chinese isEqual:@"你好欢迎你"] && c.chineseCaret == 2, @"Backspace and Forward Delete remove exactly the selected text");
        [c handleKey:6 text:@"z" modifiers:command];
        Check([c.chinese isEqual:original] && NSEqualRanges(c.markedSelection, NSMakeRange(2, 2)), @"Selected deletion is one undoable edit");
    }
    LoadDraft(c, original); SelectWorld(c);
    c.pasteText = ^{ return @""; };
    [c handleKey:9 text:@"v" modifiers:command];
    Check([c.chinese isEqual:original] && NSEqualRanges(c.markedSelection, NSMakeRange(2, 2)), @"Empty paste preserves a partial selection");
    c.pasteText = ^{ return @"API\n明天"; };
    [c handleKey:9 text:@"V" modifiers:command | shift];
    Check([c.chinese isEqual:@"你好API\n明天欢迎你"] && c.chineseCaret == 8 && !c.markedSelection.length, @"Multiline plain-text paste replaces only the selected span");
    [c handleKey:6 text:@"z" modifiers:command];
    Check([c.chinese isEqual:original] && NSEqualRanges(c.markedSelection, NSMakeRange(2, 2)), @"Undo restores the selection after paste replacement");
    for (NSString *letter in @[@"A", @"P", @"I"]) [c handleKey:0 text:letter modifiers:shift];
    [c handleModifiers:0];
    Check([c.chinese isEqual:@"你好API欢迎你"] && !c.markedSelection.length, @"Uppercase English replaces the selection and continues at the new caret");

    LoadDraft(c, original); SelectWorld(c);
    Type(c, @"z");
    Check([c.chinese isEqual:@"你好欢迎你"] && [c.engine.rawInput isEqual:@"z"] && c.chineseCaret == 2, @"New pinyin replaces only the selected text and opens candidates at that location");
    [c handleKey:6 text:@"z" modifiers:command];
    Check([c.chinese isEqual:original] && !c.engine.preedit.length && NSEqualRanges(c.markedSelection, NSMakeRange(2, 2)), @"Undoing the first replacement letter restores the original selection");
    Type(c, @"zhongguo"); Confirm(c);
    Check([c.chinese isEqual:@"你好中国欢迎你"] && c.chineseCaret == 4, @"Confirmed replacement candidates preserve both sides of the sentence");
    LoadDraft(c, original); SelectWorld(c); Type(c, @"api");
    [c handleKey:36 text:@"\r" modifiers:0];
    Check([c.chinese isEqual:@"你好api欢迎你"] && commits == 0, @"Literal English confirmation replaces the selected span without committing to the host");
    for (NSString *text in @[@" ", @",", @"3"]) {
        LoadDraft(c, original); SelectWorld(c);
        [c handleKey:[text isEqual:@" "] ? 49 : 0 text:text modifiers:0];
        NSString *replacement = [text isEqual:@","] ? @"，" : text;
        Check([c.chinese isEqual:[NSString stringWithFormat:@"你好%@欢迎你", replacement]], @"Spaces, Chinese punctuation and digits replace the selection");
    }

    LoadDraft(c, original); SelectWorld(c);
    [c handleKey:123 text:@"" modifiers:0];
    Check(c.chineseCaret == 2 && !c.markedSelection.length, @"Plain Left collapses to the selection start without moving an extra character");
    SelectWorld(c); [c handleKey:124 text:@"" modifiers:0];
    Check(c.chineseCaret == 4 && !c.markedSelection.length, @"Plain Right collapses to the selection end");
    SelectWorld(c); [c handleKey:53 text:@"" modifiers:0];
    Check([c.chinese isEqual:original] && !c.markedSelection.length && c.chineseCaret == 4, @"Escape clears the partial selection without cancelling the sentence");
    NSUInteger beforeCopies = copies;
    [c handleKey:7 text:@"x" modifiers:command];
    Check(copies == beforeCopies && [c.chinese isEqual:original], @"Cut without a selection leaves the clipboard and sentence untouched");
    [c handleKey:0 text:@"a" modifiers:command]; [c handleKey:123 text:@"" modifiers:shift];
    Check(NSEqualRanges(c.markedSelection, NSMakeRange(0, original.length - 1)), @"Shift Left can shrink a Select All range");
    [c handleKey:119 text:@"" modifiers:0];
    for (NSUInteger i = 0; i < original.length; i++) [c handleKey:123 text:@"" modifiers:shift];
    [c handleKey:7 text:@"x" modifiers:command];
    Check(!c.hasComposition && c.hasEditingSession && [clipboard isEqual:original], @"Cutting an arrow-selected whole sentence keeps an empty undoable editing session");
    [c handleKey:6 text:@"z" modifiers:command];
    Check([c.chinese isEqual:original] && c.chineseCaret == 0 && c.markedSelection.length == original.length, @"Undo restores a backward whole-sentence selection");
    [c handleKey:124 text:@"" modifiers:shift];
    Check(NSEqualRanges(c.markedSelection, NSMakeRange(1, original.length - 1)), @"A restored backward selection shrinks from the correct end");

    LoadDraft(c, @"一二三四五六七八九十\n一\n一二三四五六七八九十");
    [c handleKey:115 text:@"" modifiers:0];
    for (int i = 0; i < 8; i++) [c handleKey:124 text:@"" modifiers:0];
    [c handleKey:125 text:@"" modifiers:shift];
    Check(c.chineseCaret == 12 && NSEqualRanges(c.markedSelection, NSMakeRange(8, 4)), @"Shift Down extends to the closest position on a short next line");
    [c handleKey:125 text:@"" modifiers:shift];
    Check(c.chineseCaret == 21 && NSEqualRanges(c.markedSelection, NSMakeRange(8, 13)), @"Shift Down preserves its preferred column beyond a short line");
    [c handleKey:126 text:@"" modifiers:shift]; [c handleKey:126 text:@"" modifiers:shift];
    Check(c.chineseCaret == 8 && !c.markedSelection.length, @"Shift Up shrinks a multiline selection back to its original anchor");
    [c handleKey:126 text:@"" modifiers:shift];
    Check(c.chineseCaret == 0 && NSEqualRanges(c.markedSelection, NSMakeRange(0, 8)), @"Vertical selection can reverse across its anchor");

    view = BindSentenceView(c, 260);
    LoadDraft(c, @"我们明天下午开会讨论新的设计方案，我们明天下午开会讨论新的设计方案，我们明天下午开会讨论新的设计方案，我们明天下午开会讨论新的设计方案。");
    [c handleKey:115 text:@"" modifiers:0];
    for (int i = 0; i < 5; i++) [c handleKey:124 text:@"" modifiers:0];
    positions = SentenceGlyphPositions(view);
    for (int i = 0; i < 4; i++) [c handleKey:125 text:@"" modifiers:shift];
    Check(c.chineseCaret > 5 && NSEqualRanges(c.markedSelection, NSMakeRange(5, c.chineseCaret - 5)) && NSContainsRect(view.textView.visibleRect, view.caretRect),
        @"Shift Down selects across soft wraps and scrolls to the active endpoint");
    for (int i = 0; i < 4; i++) [c handleKey:126 text:@"" modifiers:shift];
    Check(c.chineseCaret == 5 && !c.markedSelection.length && [SentenceGlyphPositions(view) isEqual:positions], @"Wrapped selection reverses without changing text layout");

    view = BindSentenceView(c, 420);
    LoadDraft(c, @"甲👨‍👩‍👧‍👦e\u0301乙");
    [c handleKey:123 text:@"" modifiers:shift]; [c handleKey:123 text:@"" modifiers:shift];
    [c handleKey:8 text:@"c" modifiers:command];
    Check([clipboard isEqual:@"e\u0301乙"], @"Selection preserves combining marks as part of their character");
    [c handleKey:123 text:@"" modifiers:shift]; [c handleKey:8 text:@"c" modifiers:command];
    Check([clipboard isEqual:@"👨‍👩‍👧‍👦e\u0301乙"] && c.chineseCaret == 1, @"Selection never splits an emoji family");
    [c handleKey:117 text:@"" modifiers:0];
    Check([c.chinese isEqual:@"甲"] && c.chineseCaret == 1, @"Deleting a Unicode selection preserves complete surrounding characters");
    [c handleKey:123 text:@"" modifiers:shift]; [c handleKey:124 text:@"" modifiers:shift];
    [c handleKey:51 text:@"" modifiers:0];
    Check(!c.chinese.length && !c.markedSelection.length, @"Deleting after shrinking a selection to zero clears its old anchor");

    LoadDraft(c, original); SelectWorld(c); Type(c, @"shi");
    NSString *pending = c.markedText;
    NSUInteger caret = c.chineseCaret;
    for (NSNumber *key in @[@124, @125, @126, @123]) [c handleKey:key.unsignedIntegerValue text:@"" modifiers:shift];
    [c handleModifiers:0];
    Check([c.markedText isEqual:pending] && [c.engine.rawInput isEqual:@"shi"] && c.chineseCaret == caret && !c.markedSelection.length && !view.showsCaret,
        @"Shift arrows keep pending candidates active and never trigger Shift-tap literal confirmation");
    Check(commits == 0, @"Selection, clipboard editing, replacement and undo never submit the host field");
    [c cancel];
    Check(![c handleKey:123 text:@"\uf702" modifiers:shift], @"Idle Shift arrows remain native host selection");
    c.directEnglish = YES;
    Check(![c handleKey:124 text:@"\uf703" modifiers:shift], @"Direct English Shift arrows remain native host selection");
}

static void TestCommandEditing(void) {
    Composition *c = NewComposition();
    if (!c) return;
    NSEventModifierFlags command = NSEventModifierFlagCommand;
    __block NSString *clipboard = @"";
    __block NSUInteger copies = 0, commits = 0, cancels = 0;
    NSMutableArray *responses = [NSMutableArray array];
    c.copyText = ^(NSString *text) { clipboard = text; copies++; };
    c.pasteText = ^NSString *{ return clipboard; };
    c.committed = ^(NSString *text) { commits++; };
    c.cancelled = ^{ cancels++; };
    c.service = ^(NSString *text, TranslationCompletion completion) { [responses addObject:[completion copy]]; };

    Type(c, @"nihao"); Confirm(c);
    Check([c.chinese isEqual:@"你好"], @"Shortcut fixture starts with confirmed Chinese");
    [c handleKey:6 text:@"z" modifiers:command];
    Check(!c.chinese.length && [c.engine.rawInput isEqual:@"nihao"], @"Undoing candidate confirmation restores unselected pinyin");
    [c handleKey:6 text:@"Z" modifiers:command | NSEventModifierFlagShift];
    Check([c.chinese isEqual:@"你好"] && !c.engine.preedit.length, @"Redo restores the chosen Chinese without committing it to the host");
    Check(!c.engine.learningEnabled, @"Undo preserves the engine's learning preference");
    Pump(0.4);
    TranslationCompletion beforePaste = responses.lastObject;
    beforePaste(@"Hello", nil); Pump(0.02);
    Check(c.ready, @"The pre-edit translation is ready");
    Check([c handleKey:0 text:@"a" modifiers:command] && NSEqualRanges(c.markedSelection, NSMakeRange(0, 2)), @"Command A selects only the current draft");
    [c handleKey:8 text:@"c" modifiers:command];
    Check([clipboard isEqual:@"你好"] && copies == 1 && c.ready, @"Copy preserves both the draft and its ready translation");
    clipboard = @"API v2\n明天";
    [c handleKey:9 text:@"v" modifiers:command];
    Check([c.chinese isEqual:clipboard] && !c.engine.preedit.length && !c.ready, @"Paste replaces the selected draft literally, including line breaks");
    beforePaste(@"STALE", nil); Pump(0.02);
    Check(![c.english isEqual:@"STALE"], @"An earlier response cannot overwrite a pasted draft");
    [c handleKey:6 text:@"z" modifiers:command];
    Check([c.chinese isEqual:@"你好"] && c.markedSelection.length == 2, @"Undo restores replacement text and its selection");
    [c handleKey:6 text:@"Z" modifiers:command | NSEventModifierFlagShift];
    Check([c.chinese isEqual:clipboard] && c.markedSelection.length == 0, @"Shift Command Z reapplies the paste");
    Check(commits == 0 && cancels == 0, @"Editing commands neither commit nor invoke host-selection cancellation");
    [c handleKey:0 text:@"a" modifiers:command]; [c handleKey:7 text:@"x" modifiers:command];
    Check(!c.hasComposition && c.hasEditingSession && copies == 2, @"Cut keeps an empty editing session available for undo");
    [c handleKey:6 text:@"z" modifiers:command];
    Check([c.chinese isEqual:@"API v2\n明天"] && c.markedSelection.length == c.markedText.length, @"Undo after cut restores the whole selection");
    [c handleKey:0 text:@"w" modifiers:0];
    Check([c.engine.rawInput isEqual:@"w"] && !c.chinese.length, @"Typing replaces a selected draft with new pinyin");
    [c handleKey:6 text:@"Z" modifiers:command | NSEventModifierFlagShift];
    Check([c.engine.rawInput isEqual:@"w"], @"A new edit clears the redo branch");
    [c cancel];

    Type(c, @"nihaoshijie"); Confirm(c);
    [c handleKey:123 text:@"" modifiers:0]; [c handleKey:123 text:@"" modifiers:0];
    clipboard = @" API "; [c handleKey:9 text:@"v" modifiers:command];
    Check([c.chinese isEqual:@"你好 API 世界"], @"Paste inserts at a confirmed sentence's middle caret");
    [c handleKey:6 text:@"z" modifiers:command];
    Check([c.chinese isEqual:@"你好世界"] && c.chineseCaret == 2, @"Undo restores the middle insertion point");
    [c handleKey:1 text:@"s" modifiers:command];
    Check([c.chinese isEqual:@"你好世界"] && commits == 0 && [c.hint isEqual:L(@"Use ⌘A/C/X/V/Z · ⇧⌘Z redo · Insert the draft before using other shortcuts")], @"Unsupported Command keys preserve the draft without reaching host actions");
    [c cancel];

    Type(c, @"nihao");
    c.engine.caret = 2;
    clipboard = @"API"; [c handleKey:9 text:@"v" modifiers:command];
    Check([c.chinese isEqual:@"niAPIhao"] && !c.engine.preedit.length, @"Pasting within pending spelling preserves both sides as literal letters");
    [c handleKey:6 text:@"z" modifiers:command];
    Check(!c.chinese.length && [c.engine.rawInput isEqual:@"nihao"] && c.engine.caret == 2, @"Undo restores the pending spelling and its caret");
    clipboard = @""; NSString *pending = c.engine.rawInput;
    [c handleKey:9 text:@"v" modifiers:command];
    Check([c.engine.rawInput isEqual:pending] && c.engine.caret == 2, @"An empty clipboard does not change or confirm pending pinyin");
    [c cancel]; Type(c, @"xi'an");
    [c handleKey:0 text:@"a" modifiers:command]; [c handleKey:8 text:@"c" modifiers:command];
    Check([clipboard isEqual:@"xian"] && [c.engine.rawInput isEqual:@"xi'an"], @"Copy strips pinyin separators without modifying the live spelling");
    [c cancel]; Type(c, @"hello");
    [c handleModifiers:NSEventModifierFlagShift]; [c handleModifiers:0];
    [c handleKey:6 text:@"z" modifiers:command];
    Check([c.engine.rawInput isEqual:@"hello"] && !c.chinese.length, @"Shift literal confirmation is undoable as a single action");
    [c cancel];

    Type(c, @"womenmingtian");
    NSUInteger index = FindCandidate(c, @"我们");
    Check(index != NSNotFound, @"Partial-selection undo fixture finds 我们");
    if (index != NSNotFound) {
        [c chooseCandidate:index];
        NSString *literal = c.engine.literalInput;
        NSString *preedit = c.engine.preedit;
        [c expandCandidates]; [c handleKey:124 text:@"" modifiers:0];
        NSInteger highlighted = c.engine.highlighted;
        [c handleKey:0 text:@"a" modifiers:command]; [c handleKey:7 text:@"x" modifiers:command];
        Check([clipboard isEqual:literal] && !c.hasComposition, @"Cut preserves Chinese selected inside unfinished Rime input");
        [c handleKey:6 text:@"z" modifiers:command];
        Check([c.engine.preedit isEqual:preedit] && [c.engine.literalInput isEqual:literal] && c.candidatesExpanded && c.engine.highlighted == highlighted, @"Undo restores partial Chinese selection, candidate expansion and highlight");
    }
    [c cancel]; Type(c, @"shi"); [c expandCandidates]; [c changeCandidatePage:NO];
    NSInteger page = c.engine.candidatePage.index;
    [c handleKey:0 text:@"a" modifiers:command]; [c handleKey:51 text:@"" modifiers:0];
    Check(!c.hasComposition && c.hasEditingSession, @"Deleting a full selection keeps undo available");
    [c handleKey:6 text:@"z" modifiers:command];
    Check([c.engine.rawInput isEqual:@"shi"] && c.engine.candidatePage.index == page && c.candidatesExpanded, @"Undo restores a later candidate page");
    [c cancel];
    Check(!c.hasEditingSession && ![c handleKey:6 text:@"z" modifiers:command], @"Cancellation discards history so Undo cannot resurrect a draft in another field");
    Type(c, @"nihao"); Confirm(c); [c commitChinese];
    Check(commits == 1 && !c.hasEditingSession && ![c handleKey:6 text:@"z" modifiers:command], @"After explicit commit, Undo belongs to the host again");
    c.directEnglish = YES;
    Check(![c handleKey:0 text:@"a" modifiers:command] && ![c handleKey:9 text:@"v" modifiers:command], @"Direct English mode retains native host shortcuts");
}

int RunSelfTests(BOOL live) {
    @autoreleasepool {
        NSError *modelError;
        NSData *modelsJSON = [@"{\"models\":[{\"name\":\"z-model\"},{\"name\":\"a-model\"},{\"name\":\"a-model\"},{\"name\":42},{\"name\":\" \"},null]}" dataUsingEncoding:NSUTF8StringEncoding];
        Check([DecodeOllamaModels(modelsJSON, &modelError) isEqual:@[@"a-model", @"z-model"]], @"Model names are validated, deduplicated and sorted");
        Check([DecodeOllamaModels([@"{\"models\":[]}" dataUsingEncoding:NSUTF8StringEncoding], NULL) isEqual:@[]], @"Empty installed model list is valid");
        Check(DecodeOllamaModels([@"{}" dataUsingEncoding:NSUTF8StringEncoding], &modelError) == nil && modelError != nil, @"Missing model list is rejected");
        Check(DecodeOllamaModels([@"{\"models\":42}" dataUsingEncoding:NSUTF8StringEncoding], NULL) == nil, @"Wrong model list type is rejected");
        Check(DecodeOllamaModels([@"invalid" dataUsingEncoding:NSUTF8StringEncoding], NULL) == nil, @"Malformed model response is rejected");
        Composition *c = NewComposition();
        if (!c) return 1;
        NSMutableArray *commits = [NSMutableArray array];
        c.committed = ^(NSString *text) { [commits addObject:text]; };
        Check(![c handleKey:48 text:@"\t" modifiers:0], @"Tab passes through with no composition");
        Check(![c handleKey:36 text:@"\r" modifiers:0], @"Return passes through with no composition");
        Type(c, @"nihao");
        Check([c.engine.candidates containsObject:@"你好"], @"Real pinyin dictionary offers nihao → 你好");
        [c handleKey:48 text:@"\t" modifiers:0];
        Check(!commits.count && c.engine.preedit.length, @"Unselected pinyin cannot commit via Tab");
        NSUInteger index = [c.engine.candidates indexOfObject:@"你好"];
        if (index != NSNotFound) [c chooseCandidate:index];
        Check([c.chinese isEqual:@"你好"] && !commits.count, @"Chinese selection stays in sentence buffer");
        [c handleKey:48 text:@"\t" modifiers:0];
        Check(!commits.count, @"Early Tab never queues automatic commit");
        Pump(0.5);
        Check(c.ready && !commits.count, @"Translation readiness does not auto-commit");
        [c handleKey:48 text:@"\t" modifiers:0];
        Check([commits isEqual:@[@"Hello"]] && !c.hasComposition, @"Tab commits English exactly once without Return");

        Type(c, @"womenmingtianxiawukaihui");
        Confirm(c);
        Check([c.chinese isEqual:@"我们明天下午开会"], @"Continuous full-sentence pinyin converts correctly");
        [c handleKey:0 text:@"." modifiers:0];
        Check([c.chinese hasSuffix:@"。"] && commits.count == 1, @"Punctuation stays in buffer");
        [c handleKey:36 text:@"\r" modifiers:0];
        Check([commits.lastObject isEqual:@"我们明天下午开会。"] && commits.count == 2, @"Enter commits Chinese without submitting host form");

        NSMutableArray *pending = [NSMutableArray array];
        c.service = ^(NSString *text, TranslationCompletion completion) { [pending addObject:[completion copy]]; };
        Type(c, @"nihao"); Confirm(c); Pump(0.5);
        Check(pending.count == 1, @"Debounced translation is issued");
        [c handleKey:51 text:@"" modifiers:0];
        Check([c.chinese isEqual:@"你"], @"Backspace removes last confirmed character");
        Pump(0.5);
        if (pending.count == 2) {
            TranslationCompletion old = pending[0];
            old(@"STALE", nil);
            Pump(0.03);
            Check(!c.ready && !c.english.length, @"Old translation cannot replace a revised sentence");
            TranslationCompletion latest = pending[1];
            latest(@"You", nil);
            Pump(0.03);
            Check(c.ready && [c.english isEqual:@"You"], @"Latest translation becomes selectable");
        } else Check(NO, @"Second translation request is issued");
        Type(c, @"hao");
        Check(!c.ready, @"Pending pinyin prevents committing a partial translation");
        [c handleKey:53 text:@"" modifiers:0];
        Check([c.chinese isEqual:@"你"] && !c.engine.preedit.length, @"First Escape clears pending pinyin only");
        [c handleKey:53 text:@"" modifiers:0];
        Check(!c.hasComposition && !c.english.length, @"Second Escape cancels the sentence");
        Type(c, @"huancun"); Confirm(c); Pump(0.5);
        Check([c.chinese isEqual:@"缓存"], @"Single-word translation uses the same pinyin flow");
        TranslationCompletion delayed = pending.lastObject;
        [c cancel];
        delayed(@"cache", nil);
        Pump(0.03);
        Check(!c.ready && !c.english.length && commits.count == 2, @"Focus cancellation discards delayed translations");
        Type(c, @"ni");
        Check([c handleKey:8 text:@"c" modifiers:NSEventModifierFlagCommand] && [c.engine.rawInput isEqual:@"ni"], @"Command editing preserves the uncommitted spelling");
        [c cancel];

        c.service = ^(NSString *text, TranslationCompletion completion) { completion(nil, [NSError errorWithDomain:@"test" code:1 userInfo:nil]); };
        Type(c, @"nihao"); Confirm(c); Pump(0.5);
        Check(!c.ready && [c.hint isEqual:L(@"Translation failed. Retry from the input menu; Enter still inserts the source.")], @"Translation failure remains visible and cannot commit English");
        [c commitChinese];
        Check([commits.lastObject isEqual:@"你好"], @"Chinese commit still works after translation failure");

        TestShiftAndPunctuation();
        TestCandidateNavigation();
        TestArrowOwnership();
        TestTextEditing();
        TestSentenceNavigation();
        TestCandidateLayout();
        TestMixedInput();
        TestCommandEditing();
        TestPartialSelection();
        if (live) {
            NSUserDefaults *preferences = NSUserDefaults.standardUserDefaults;
            NSDictionary *original = [preferences volatileDomainForName:NSArgumentDomain];
            NSMutableDictionary *arguments = [original mutableCopy];
            arguments[@"translationSourceLanguage"] = @"auto";
            arguments[@"translationTargetLanguage"] = @"en";
            [preferences setVolatileDomain:arguments forName:NSArgumentDomain];
            @try {
                Composition *real = NewComposition();
                real.service = nil;
                Type(real, @"womenmingtianxiawukaihui"); Confirm(real);
                NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:40];
                while (!real.ready && deadline.timeIntervalSinceNow > 0) Pump(0.05);
                Check(real.ready && [real.english rangeOfString:@"tomorrow" options:NSCaseInsensitiveSearch].location != NSNotFound, @"Real Ollama translation succeeds");
                if (real.ready) printf("Live translation: %s\n", real.english.UTF8String);
                [real cancel];
            } @finally { [preferences setVolatileDomain:original forName:NSArgumentDomain]; }
        }
        [c cancel];
        printf("%d checks, %d failures\n", checks, failures);
    }
    return failures ? 1 : 0;
}

// Exercise the production candidate view without an active IMK client.
@interface CandidatePreviewWindow : NSWindow
@property(nonatomic, strong) Composition *composition;
@end
@implementation CandidatePreviewWindow
- (void)sendEvent:(NSEvent *)event {
    if (event.type == NSEventTypeFlagsChanged && [_composition handleModifiers:event.modifierFlags]) return;
    if (event.type == NSEventTypeKeyDown) {
        if ([_composition handleKey:event.keyCode text:event.characters ?: @"" modifiers:event.modifierFlags]) return;
    }
    [super sendEvent:event];
}
@end

void ShowCandidatePreview(void) {
    static CandidatePreviewWindow *window;
    window = [[CandidatePreviewWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 280) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    window.title = L(@"{appName} Candidate Preview");
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--light-preview"])
        window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    window.releasedWhenClosed = NO;
    window.composition = [Composition new];
    window.composition.directEnglish = NO;
    window.composition.engine.learningEnabled = NO;
    window.composition.service = ^(NSString *source, TranslationCompletion done) { done(@"Hello, we will discuss the new input method tomorrow. Use the arrow keys to move the cursor after choosing candidates.", nil); };
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--live-preview"]) window.composition.service = nil;
    // Exercise clipboard commands without changing the user's system clipboard.
    __block NSString *previewClipboard = @"";
    window.composition.copyText = ^(NSString *text) { previewClipboard = text; };
    window.composition.pasteText = ^{ return previewClipboard; };
    CandidateListView *list = [[CandidateListView alloc] initWithFrame:NSZeroRect];
    SentenceView *draft = [[SentenceView alloc] initWithFrame:NSMakeRect(0, 0, 560, 24)];
    NSTextField *hint = [NSTextField wrappingLabelWithString:L(@"Arrows: choose · ↑ ↓ expand · After choosing, arrows edit the sentence")];
    hint.textColor = NSColor.secondaryLabelColor;
    NSTextField *inputMode = [NSTextField wrappingLabelWithString:@""];
    inputMode.font = [NSFont systemFontOfSize:11];
    inputMode.textColor = NSColor.secondaryLabelColor;
    [inputMode setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *header = CreateCompositionHeader(inputMode);
    NSTextField *translation = [NSTextField wrappingLabelWithString:@""];
    translation.font = [NSFont systemFontOfSize:16];
    translation.maximumNumberOfLines = 3;
    [translation setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSStackView *englishRow = CreateLanguageRow(L(@"EN"), translation);
    NSBox *separator = [NSBox new];
    separator.boxType = NSBoxSeparator;
    NSStackView *stack = [NSStackView stackViewWithViews:@[header, draft, list, separator, englishRow, hint]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [window.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:20],
        [draft.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [header.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [englishRow.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [separator.widthAnchor constraintEqualToAnchor:stack.widthAnchor]
    ]];
    __weak Composition *composition = window.composition;
    list.choose = ^(NSUInteger index) { [composition chooseCandidate:index]; };
    list.changePage = ^(BOOL backward) { [composition changeCandidatePage:backward]; };
    list.setExpanded = ^(BOOL expanded) { if (expanded) [composition expandCandidates]; else [composition collapseCandidates]; };
    window.composition.changed = ^{
        [list updateWithPage:composition.engine.candidatePage expanded:composition.candidatesExpanded columns:composition.candidateColumns];
        [draft updateWithComposition:composition];
        hint.stringValue = composition.hint;
        inputMode.stringValue = composition.inputModeDescription;
        translation.stringValue = composition.english.length ? composition.english : L(@"Waiting for translation…");
        UpdateTranslationLanguageRow(englishRow, composition.translationTargetLanguage);
        translation.textColor = composition.english.length ? NSColor.labelColor : NSColor.secondaryLabelColor;
        [window setContentSize:NSMakeSize(MAX(448, list.contentWidth + 40), MAX(320, list.fittingSize.height + 200))];
    };
    window.composition.moveSentenceCaret = ^NSUInteger(NSUInteger caret, NSInteger delta) { return [draft moveCaret:caret byLines:delta]; };
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--sentence-preview"]) {
        window.title = L(@"{appName} Sentence Preview");
        Type(window.composition, @"nihao"); Confirm(window.composition);
        [window.composition appendLiteral:@"，我们明天下午开会讨论新的输入法交互。候选选完后，可以使用上下左右键移动光标；移动光标不会挤动文字。 Hello, world! 👨‍👩‍👧‍👦"];
    } else Type(window.composition, @"shi");
    [window.composition synchronizeModifiers:NSEvent.modifierFlags];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [window center];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
