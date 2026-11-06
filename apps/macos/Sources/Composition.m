#import "Core.h"
#import "KeyboardLayoutEngine.h"

static BOOL IsPrintableInput(NSString *text) {
    if (!text.length || [text rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return NO;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar character = [text characterAtIndex:i];
        if (character >= 0xf700 && character <= 0xf8ff) return NO;
    }
    return YES;
}

@implementation Composition {
    NSString *_translatedSource;
    NSUInteger _revision;
    NSURLSessionDataTask *_request;
    NSEventModifierFlags _lastModifiers;
    BOOL _shiftCanConfirm;
    BOOL _closeSingleQuote;
    BOOL _closeDoubleQuote;
    BOOL _draftCloseSingleQuote;
    BOOL _draftCloseDoubleQuote;
    BOOL _allSelected;
    NSUInteger _selectionAnchor;
    NSMutableArray *_undoEdits;
    NSMutableArray *_redoEdits;
    NSUInteger _editDepth;
    NSUInteger _historyGeneration;
    NSUInteger _editGeneration;
    NSDictionary *_editBefore;
    BOOL _skipHistory;
    KeyboardLayoutEngine *_keyboard;
}
- (instancetype)init {
    if ((self = [super init])) {
        _lastModifiers = NSEvent.modifierFlags;
        _baseInputLanguage = InputLanguageForModifiers(_lastModifiers);
        _engine = [[PinyinEngine alloc] initWithLanguage:_baseInputLanguage];
        if (!_engine) return nil;
        _keyboard = [KeyboardLayoutEngine new];
        _chinese = @"";
        _english = @"";
        _translationSourceLanguage = @"auto";
        _translationTargetLanguage = PairTranslationTarget(@"", _baseInputLanguage);
        _selectionAnchor = NSNotFound;
        _undoEdits = [NSMutableArray array];
        _redoEdits = [NSMutableArray array];
        _candidateColumns = ReadCandidateColumns();
        _hint = L(@"Space / numbers: choose · Esc: cancel draft");
    }
    return self;
}
- (void)dealloc { [_request cancel]; }
- (BOOL)hasComposition { return _chinese.length || _engine.preedit.length; }
- (BOOL)hasEditingSession { return self.hasComposition || _undoEdits.count || _redoEdits.count; }
- (NSString *)inputLanguage { return _baseInputLanguage; }
- (BOOL)inputEnglish { return [self.inputLanguage isEqual:@"en"]; }
- (BOOL)directEnglish { return [_baseInputLanguage isEqual:@"en"]; }
- (NSString *)inputModeDescription { return TranslationLanguageName(self.inputLanguage); }
- (BOOL)ready { return !_engine.preedit.length && !_keyboard.hasPendingAccent && _english.length && [_translatedSource isEqual:_chinese]; }
- (NSString *)pendingKeyboardText { return _keyboard.pendingText; }
- (NSString *)markedText {
    return [_chinese stringByReplacingCharactersInRange:NSMakeRange(_chineseCaret, 0) withString:[_engine.preedit stringByAppendingString:self.pendingKeyboardText]];
}
- (NSUInteger)markedCaret { return _chineseCaret + _engine.preeditCaret + self.pendingKeyboardText.length; }
- (NSRange)sentenceSelection {
    if (_selectionAnchor == NSNotFound) return NSMakeRange(_chineseCaret, 0);
    return NSMakeRange(MIN(_selectionAnchor, _chineseCaret), MAX(_selectionAnchor, _chineseCaret) - MIN(_selectionAnchor, _chineseCaret));
}
- (NSRange)markedSelection {
    if (_allSelected) return NSMakeRange(0, self.markedText.length);
    return _engine.preedit.length || _keyboard.hasPendingAccent ? NSMakeRange(self.markedCaret, 0) : self.sentenceSelection;
}
- (void)clearSelection { _allSelected = NO; _selectionAnchor = NSNotFound; }
- (void)notify { if (_changed) _changed(); }
- (void)setCandidateColumns:(NSInteger)candidateColumns {
    NSInteger valid = candidateColumns >= MinimumCandidateColumns && candidateColumns <= MaximumCandidateColumns ? candidateColumns : DefaultCandidateColumns;
    if (_candidateColumns == valid) return;
    _candidateColumns = valid;
    [self collapseCandidates];
}
- (void)setDirectEnglish:(BOOL)directEnglish { self.baseInputLanguage = directEnglish ? @"en" : @"zh"; }
- (BOOL)prepareEngineForLanguage:(NSString *)language {
    if (!InputLanguageUsesCandidates(language) || [_engine.language isEqual:language]) return YES;
    PinyinEngine *engine = [[PinyinEngine alloc] initWithLanguage:language];
    if (!engine) { _hint = L(@"Could not load the input engine. Your draft is preserved."); return NO; }
    engine.learningEnabled = _engine.learningEnabled;
    // Preserve any unfinished spelling before changing script-specific schemas.
    if (_engine.preedit.length) {
        [self clearSelection];
        [self materializePendingForEditing];
        [self scheduleTranslation];
    }
    _engine = engine;
    return YES;
}
- (void)finishSourceBeforeLanguageChange {
    [self flushKeyboardPending];
    if (!self.hasEditingSession) return;
    // Resolve the highlighted candidate at the current sentence caret. Do not
    // start translations or render intermediate candidates while committing.
    [self clearSelection];
    NSUInteger remaining = _engine.rawInput.length + 1;
    while (_engine.preedit.length && remaining--) {
        NSString *before = _engine.preedit;
        NSInteger highlighted = _engine.candidatePage.highlighted;
        if (highlighted == NSNotFound || ![_engine choose:highlighted]) break;
        NSString *commit = [_engine takeCommit];
        if (commit.length) [self insertIntoDraft:commit];
        if ([_engine.preedit isEqual:before] && !commit.length) break;
    }
    // Incomplete or unconvertible spelling must never disappear on a switch.
    if (_engine.preedit.length) {
        NSString *literal = _engine.literalInput;
        [_engine clear];
        if (literal.length) [self insertIntoDraft:literal];
    }
    if (_chinese.length) [self commitText:_chinese];
    else [self cancel];
}
- (void)setBaseInputLanguage:(NSString *)language {
    if ([_baseInputLanguage isEqual:language]) return;
    [self finishSourceBeforeLanguageChange];
    if (![self prepareEngineForLanguage:language]) { [self notify]; return; }
    _baseInputLanguage = language.copy;
    [_keyboard reset];
    _shiftCanConfirm = NO;
    [self notify];
}
- (void)synchronizeModifiers:(NSEventModifierFlags)flags {
    _lastModifiers = flags;
    _shiftCanConfirm = NO;
    self.baseInputLanguage = InputLanguageForModifiers(flags);
}
- (BOOL)handleModifiers:(NSEventModifierFlags)flags {
    if (flags == _lastModifiers && [self.inputLanguage isEqual:InputLanguageForModifiers(flags)]) return NO;
    [self beginEdit];
    @try { return [self processModifiers:flags]; }
    @finally { [self endEdit]; }
}
- (BOOL)processModifiers:(NSEventModifierFlags)flags {
    BOOL capsChanged = ((_lastModifiers ^ flags) & NSEventModifierFlagCapsLock) != 0;
    BOOL wasShift = (_lastModifiers & NSEventModifierFlagShift) != 0;
    BOOL isShift = (flags & NSEventModifierFlagShift) != 0;
    NSString *language = InputLanguageForModifiers(flags);
    BOOL languageChanged = ![self.inputLanguage isEqual:language];
    if (capsChanged || languageChanged) {
        _lastModifiers = flags;
        _shiftCanConfirm = NO;
        self.baseInputLanguage = language;
        return YES;
    }
    if (!wasShift && isShift) _shiftCanConfirm = InputLanguageUsesCandidates(self.inputLanguage) && !self.markedSelection.length && _engine.preedit.length;
    if (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) _shiftCanConfirm = NO;
    _lastModifiers = flags;
    if (wasShift && !isShift) {
        BOOL confirm = _shiftCanConfirm;
        _shiftCanConfirm = NO;
        if (confirm && _engine.preedit.length) { [self confirmPendingLiteral]; return YES; }
    }
    return NO;
}
- (void)scheduleTranslation {
    [_request cancel];
    NSUInteger revision = ++_revision;
    _english = @"";
    _translatedSource = nil;
    _translationSourceLanguage = @"auto";
    _translationTargetLanguage = PairTranslationTarget(_chinese, self.inputLanguage);
    _hint = _chinese.length ? L(@"Translating this sentence…") : L(@"Confirm text to see its translation");
    if (!_chinese.length) return;
    NSString *source = [_chinese copy];
    NSString *sourceLanguage = _translationSourceLanguage;
    NSString *targetLanguage = _translationTargetLanguage;
    __weak Composition *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        Composition *self = weakSelf;
        if (!self || self->_revision != revision) return;
        TranslationCompletion finish = ^(NSString *translated, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                Composition *self = weakSelf;
                if (!self || self->_revision != revision || ![self->_chinese isEqual:source]) return;
                NSString *clean = TranslationWithSourceLayout(translated, source);
                if (error || !clean.length) {
                    self->_hint = [error.domain isEqual:@"DualLineIME.Provider"] ? [error.localizedDescription stringByAppendingString:L(@" Enter still inserts the source.")] : L(@"Translation failed. Retry from the input menu; Enter still inserts the source.");
                    self->_english = @"";
                } else {
                    self->_translatedSource = source;
                    self->_english = clean;
                    self->_hint = L(@"Arrows: move · Shift + arrows: select · Esc: cancel");
                }
                [self notify];
            });
        };
        if (self.service) { self.service(source, finish); return; }
        self->_request = TranslateTextWithLanguages(source, sourceLanguage, targetLanguage, finish);
    });
}
- (void)collectCommit {
    _candidatesExpanded = NO;
    NSString *commit = [_engine takeCommit];
    if (commit.length) {
        [self insertIntoDraft:commit];
        [self scheduleTranslation];
    }
    [self notify];
}
- (void)confirmPendingLiteral {
    // Preserve selected segments and confirm only the remaining spelling literally.
    NSString *literal = _engine.literalInput;
    [_engine clear];
    _candidatesExpanded = NO;
    _shiftCanConfirm = NO;
    if (literal.length) {
        [self insertIntoDraft:literal];
        [self scheduleTranslation];
    }
    [self notify];
}
- (void)chooseCandidate:(NSUInteger)index {
    [self beginEdit];
    @try {
    NSUInteger visible = _candidatesExpanded ? _engine.candidates.count : MIN((NSUInteger)_candidateColumns, _engine.candidates.count);
    if (index >= visible) return;
    [self clearSelection];
    if ([_engine choose:index]) [self collectCommit];
    } @finally { [self endEdit]; }
}
- (void)expandCandidates {
    if (!_engine.candidates.count) return;
    _candidatesExpanded = YES;
    [self notify];
}
- (void)collapseCandidates {
    _candidatesExpanded = NO;
    _shiftCanConfirm = NO;
    NSInteger highlighted = _engine.highlighted;
    if (highlighted != NSNotFound && highlighted >= _candidateColumns)
        [_engine moveHighlight:_candidateColumns - 1 - highlighted];
    [self notify];
}
- (void)changeCandidatePage:(BOOL)backward {
    if (!_candidatesExpanded) { [self expandCandidates]; return; }
    [_engine changePage:backward];
    [self notify];
}
- (void)moveCandidateHorizontally:(NSInteger)horizontal vertically:(NSInteger)vertical {
    CandidatePage *page = _engine.candidatePage;
    _hint = L(@"Arrows: choose · Space: confirm · Then use arrows to edit the sentence");
    if (!page.candidates.count) { [self notify]; return; }
    if (!_candidatesExpanded && vertical) { [self expandCandidates]; return; }
    NSInteger current = page.highlighted;
    NSInteger count = page.candidates.count;
    NSInteger target = current + horizontal + vertical * _candidateColumns;
    if (!_candidatesExpanded && target >= _candidateColumns) _candidatesExpanded = YES;
    if (target >= 0 && target < count) {
        [_engine moveHighlight:target - current];
    } else if (target >= count && vertical && current / _candidateColumns < (count - 1) / _candidateColumns) {
        // Keep the highlight on a real item in a partially filled final row.
        [_engine moveHighlight:count - 1 - current];
    } else if (target >= count && page.hasNextPage && [_engine changePage:NO]) {
        _candidatesExpanded = YES;
        NSInteger next = vertical ? current % _candidateColumns : 0;
        next = MIN(next, (NSInteger)_engine.candidates.count - 1);
        [_engine moveHighlight:next - _engine.highlighted];
    } else if (target < 0 && page.hasPreviousPage && [_engine changePage:YES]) {
        NSInteger previousCount = _engine.candidates.count;
        NSInteger previous = vertical ? ((previousCount - 1) / _candidateColumns) * _candidateColumns + current % _candidateColumns : previousCount - 1;
        previous = MIN(previous, previousCount - 1);
        _candidatesExpanded = YES;
        [_engine moveHighlight:previous - _engine.highlighted];
    }
    [self notify];
}
- (void)reset {
    ++_historyGeneration;
    [_undoEdits removeAllObjects];
    [_redoEdits removeAllObjects];
    [self clearSelection];
    ++_revision;
    [_request cancel];
    [_engine clear];
    _chinese = @"";
    _chineseCaret = 0;
    _english = @"";
    _translatedSource = nil;
    _candidatesExpanded = NO;
    _shiftCanConfirm = NO;
    [_keyboard reset];
    [self prepareEngineForLanguage:_baseInputLanguage];
}
- (void)cancel {
    BOOL hadContent = self.hasEditingSession;
    if (!hadContent) [self flushKeyboardPending];
    if (hadContent) {
        _closeSingleQuote = _draftCloseSingleQuote;
        _closeDoubleQuote = _draftCloseDoubleQuote;
    }
    [self reset];
    if (hadContent && _cancelled) _cancelled();
    [self notify];
}
- (void)commitText:(NSString *)text {
    NSString *result = [text copy];
    if (_inputLanguageCommitted && [_translationSourceLanguage isEqual:@"auto"]) {
        NSString *language = DetectInputLanguage(_chinese);
        if (language) _inputLanguageCommitted(language);
    }
    [self reset];
    if (_committed) _committed(result);
    [self notify];
}
- (void)commitEnglish {
    [self flushKeyboardPending];
    if (self.ready) [self commitText:_english];
    else { _hint = _engine.preedit.length ? L(@"Confirm candidates with Space or a number first") : L(@"Translation is not ready. Press Tab again when it finishes."); [self notify]; }
}
- (void)commitChinese {
    [self flushKeyboardPending];
    if (!_engine.preedit.length && _chinese.length) [self commitText:_chinese];
    else if (!self.hasComposition && self.hasEditingSession) [self cancel];
    else { _hint = L(@"Confirm candidates with Space or a number first"); [self notify]; }
}
- (void)retry { [self scheduleTranslation]; [self notify]; }
- (void)insertIntoDraft:(NSString *)text {
    NSRange range = self.sentenceSelection;
    _chinese = [_chinese stringByReplacingCharactersInRange:range withString:text];
    _chineseCaret = range.location + text.length;
    [self clearSelection];
}
- (void)moveTextCaret:(NSUInteger)code {
    [self moveTextCaret:code extending:NO];
}
- (void)moveTextCaret:(NSUInteger)code extending:(BOOL)extending {
    _candidatesExpanded = NO;
    if (_engine.preedit.length) {
        [self clearSelection];
        NSUInteger caret = _engine.caret;
        if (code == 115) caret = 0;
        else if (code == 119) caret = _engine.rawInput.length;
        else if (code == 123 && caret) caret--;
        else if (code == 124 && caret < _engine.rawInput.length) caret++;
        _engine.caret = caret;
    } else {
        NSRange selection = self.sentenceSelection;
        BOOL collapse = !extending && selection.length && (code == 123 || code == 124);
        if (extending) {
            if (_selectionAnchor == NSNotFound) _selectionAnchor = _chineseCaret;
        } else [self clearSelection];
        if (collapse) _chineseCaret = code == 123 ? selection.location : NSMaxRange(selection);
        else if (code == 115) _chineseCaret = 0;
        else if (code == 119) _chineseCaret = _chinese.length;
        else if (code == 123 && _chineseCaret)
            _chineseCaret = [_chinese rangeOfComposedCharacterSequenceAtIndex:_chineseCaret - 1].location;
        else if (code == 124 && _chineseCaret < _chinese.length)
            _chineseCaret = NSMaxRange([_chinese rangeOfComposedCharacterSequenceAtIndex:_chineseCaret]);
        if (_moveSentenceCaret) {
            NSInteger delta = code == 125 ? 1 : code == 126 ? -1 : 0;
            _chineseCaret = MIN(_chinese.length, _moveSentenceCaret(_chineseCaret, delta));
            if (_chineseCaret < _chinese.length)
                _chineseCaret = [_chinese rangeOfComposedCharacterSequenceAtIndex:_chineseCaret].location;
        }
        _hint = self.markedSelection.length ? L(@"Text selected · ⌘C copy · ⌘X cut · Type or paste to replace · Esc deselect")
            : L(@"Arrows: move · Shift + arrows: select · Tab / Enter: insert");
    }
    [self notify];
}
- (void)deleteFromDraftForward:(BOOL)forward {
    [self clearSelection];
    if (forward ? _chineseCaret == _chinese.length : _chineseCaret == 0) return;
    NSRange range = [_chinese rangeOfComposedCharacterSequenceAtIndex:forward ? _chineseCaret : _chineseCaret - 1];
    NSString *removed = [_chinese substringWithRange:range];
    if ([removed isEqual:@"“"] || [removed isEqual:@"”"]) _closeDoubleQuote = [removed isEqual:@"”"];
    if ([removed isEqual:@"‘"] || [removed isEqual:@"’"]) _closeSingleQuote = [removed isEqual:@"’"];
    _chinese = [_chinese stringByReplacingCharactersInRange:range withString:@""];
    _chineseCaret = range.location;
    [self scheduleTranslation];
}
- (void)appendLiteral:(NSString *)text {
    [self beginEdit];
    @try {
    if (self.hasEditingSession) {
        [self insertIntoDraft:text];
        [self scheduleTranslation];
        [self notify];
    } else {
        if (_committed) _committed(text);
    }
    } @finally { [self endEdit]; }
}

- (NSDictionary *)editSnapshot {
    return @{@"chinese":_chinese, @"caret":@(_chineseCaret), @"engine":[_engine editingState],
        @"selected":@(_allSelected), @"anchor":@(_selectionAnchor), @"expanded":@(_candidatesExpanded),
        @"single":@(_closeSingleQuote), @"double":@(_closeDoubleQuote),
        @"draftSingle":@(_draftCloseSingleQuote), @"draftDouble":@(_draftCloseDoubleQuote)};
}
- (void)beginEdit {
    if (_editDepth++ != 0) return;
    // Direct typing has no local edit history; avoid querying Rime for each letter.
    _editBefore = self.hasEditingSession || InputLanguageUsesCandidates(self.inputLanguage) ? [self editSnapshot] : nil;
    _editGeneration = _historyGeneration;
    _skipHistory = NO;
}
- (void)endEdit {
    if (--_editDepth != 0) return;
    if (_editBefore && !_skipHistory && _editGeneration == _historyGeneration &&
        (![_editBefore[@"chinese"] isEqual:_chinese] ||
         ![_editBefore[@"engine"][@"raw"] isEqual:_engine.rawInput] ||
         ![_editBefore[@"engine"][@"literal"] isEqual:_engine.literalInput])) {
        [_undoEdits addObject:_editBefore];
        if (_undoEdits.count > 100) [_undoEdits removeObjectAtIndex:0];
        [_redoEdits removeAllObjects];
        [self notify];
    }
    _editBefore = nil;
}
- (void)restoreEditBackward:(BOOL)backward {
    _skipHistory = YES;
    NSMutableArray *from = backward ? _undoEdits : _redoEdits;
    NSMutableArray *to = backward ? _redoEdits : _undoEdits;
    NSDictionary *snapshot = from.lastObject;
    if (!snapshot) { _hint = backward ? L(@"Nothing to undo") : L(@"Nothing to redo"); [self notify]; return; }
    // Rebuild in another session so a failed restore never damages the current draft.
    PinyinEngine *restored = [[PinyinEngine alloc] initWithLanguage:snapshot[@"engine"][@"language"]];
    restored.learningEnabled = _engine.learningEnabled;
    if (!restored || ![restored restoreEditingState:snapshot[@"engine"]]) {
        _hint = L(@"Could not restore this edit. Your draft is preserved."); [self notify]; return;
    }
    [to addObject:[self editSnapshot]];
    [from removeLastObject];
    _engine = restored;
    _chinese = snapshot[@"chinese"];
    _chineseCaret = [snapshot[@"caret"] unsignedIntegerValue];
    _allSelected = [snapshot[@"selected"] boolValue];
    _selectionAnchor = [snapshot[@"anchor"] unsignedIntegerValue];
    _candidatesExpanded = [snapshot[@"expanded"] boolValue];
    [_keyboard reset];
    _closeSingleQuote = [snapshot[@"single"] boolValue];
    _closeDoubleQuote = [snapshot[@"double"] boolValue];
    _draftCloseSingleQuote = [snapshot[@"draftSingle"] boolValue];
    _draftCloseDoubleQuote = [snapshot[@"draftDouble"] boolValue];
    [self scheduleTranslation];
    [self notify];
}
- (void)clearDraftForEditing {
    [_engine clear];
    _chinese = @"";
    _chineseCaret = 0;
    [self clearSelection];
    _candidatesExpanded = NO;
    _closeSingleQuote = _draftCloseSingleQuote;
    _closeDoubleQuote = _draftCloseDoubleQuote;
    [self scheduleTranslation];
    _hint = L(@"⌘Z undo · Continue typing or paste · Esc end draft");
}
- (void)deleteSelection {
    NSRange range = self.sentenceSelection;
    if (_allSelected || (range.length && range.length == _chinese.length)) {
        [self clearDraftForEditing];
    } else if (range.length) {
        [self insertIntoDraft:@""];
        [self scheduleTranslation];
    }
}
- (void)materializePendingForEditing {
    if (!_engine.preedit.length) return;
    NSString *literal = _engine.literalInput;
    NSUInteger caret = _chineseCaret + _engine.literalCaret;
    [self insertIntoDraft:literal];
    _chineseCaret = MIN(caret, _chinese.length);
    [_engine clear];
    _candidatesExpanded = NO;
}
- (BOOL)handleCommand:(NSUInteger)code modifiers:(NSEventModifierFlags)flags {
    BOOL shift = (flags & NSEventModifierFlagShift) != 0;
    BOOL plain = !(flags & (NSEventModifierFlagControl | NSEventModifierFlagOption));
    if (plain && code == 6) { [self restoreEditBackward:!shift]; return YES; }
    if (plain && !shift && code == 0) {
        [self clearSelection];
        if (_engine.preedit.length) _allSelected = YES;
        else { _selectionAnchor = 0; _chineseCaret = _chinese.length; }
        _hint = L(@"Draft selected · ⌘C copy · ⌘X cut · ⌘V replace · ⌘Z undo");
        [self notify]; return YES;
    }
    if (plain && !shift && (code == 8 || code == 7)) {
        if (!self.markedSelection.length) { _hint = L(@"Select with Shift + arrows or ⌘A before copying or cutting"); [self notify]; return YES; }
        NSString *text = _allSelected ? [_chinese stringByReplacingCharactersInRange:NSMakeRange(_chineseCaret, 0) withString:_engine.literalInput]
            : [_chinese substringWithRange:self.sentenceSelection];
        if (!_copyText) { _hint = L(@"Could not copy. Your draft is preserved."); [self notify]; return YES; }
        _copyText(text);
        if (code == 7) [self deleteSelection];
        else _hint = L(@"Selected text copied");
        [self notify]; return YES;
    }
    if (plain && code == 9) {
        NSString *text = _pasteText ? _pasteText() : nil;
        if (!text.length) { _hint = L(@"No text to paste from the clipboard"); [self notify]; return YES; }
        if (self.markedSelection.length) [self deleteSelection]; else [self materializePendingForEditing];
        [self insertIntoDraft:text];
        [self scheduleTranslation];
        [self notify]; return YES;
    }
    if (plain && !shift && (code == 123 || code == 124)) {
        [self clearSelection];
        [self moveTextCaret:code == 123 ? 115 : 119];
        return YES;
    }
    // Do not let a host command delete or submit the current marked text.
    _hint = L(@"Use ⌘A/C/X/V/Z · ⇧⌘Z redo · Insert the draft before using other shortcuts");
    [self notify]; return YES;
}
- (NSString *)chinesePunctuation:(NSString *)text {
    if ([self.inputLanguage isEqual:@"ja"]) {
        if ([text isEqual:@"\""]) {
            NSString *quote = _closeDoubleQuote ? @"」" : @"「";
            _closeDoubleQuote = !_closeDoubleQuote;
            return quote;
        }
        return @{@",":@"、", @".":@"。", @"!":@"！", @"?":@"？", @"(":@"（", @")":@"）", @"[":@"「", @"]":@"」", @"<":@"〈", @">":@"〉", @":":@"：", @";":@"；"}[text] ?: text;
    }

    if ([text isEqual:@"\""]) {
        NSString *quote = _closeDoubleQuote ? @"”" : @"“";
        _closeDoubleQuote = !_closeDoubleQuote;
        return quote;
    }
    if ([text isEqual:@"'"]) {
        NSString *quote = _closeSingleQuote ? @"’" : @"‘";
        _closeSingleQuote = !_closeSingleQuote;
        return quote;
    }
    NSDictionary *punctuation = @{@",":@"，", @".":@"。", @"!":@"！", @"?":@"？", @";":@"；", @":":@"：",
        @"(":@"（", @")":@"）", @"[":@"【", @"]":@"】", @"<":@"《", @">":@"》", @"\\":@"、",
        @"^":@"……", @"_":@"——", @"`":@"·", @"~":@"～"};
    return punctuation[text] ?: text;
}
- (BOOL)handleKey:(NSUInteger)code text:(NSString *)text modifiers:(NSEventModifierFlags)flags {
    [self handleModifiers:flags];
    [self beginEdit];
    @try {
        return [self processKey:code text:text modifiers:flags layoutText:NO];
    }
    @finally { [self endEdit]; }
}
- (BOOL)handlePhysicalKey:(NSUInteger)code text:(NSString *)text modifiers:(NSEventModifierFlags)flags {
    // Finish a language transition before the new key's layout mapping and undo entry.
    [self handleModifiers:flags];
    // Finish the pending character as its own edit before applying clipboard/undo commands.
    if (_keyboard.hasPendingAccent && (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl)))
        [self flushKeyboardPending];
    [self beginEdit];
    @try {
        NSString *language = self.inputLanguage;
        _keyboard.language = language;
        BOOL useLayout = ![language isEqual:@"en"] && KeyboardLayoutIdentifierForLanguage(language) != nil;
        BOOL replacingSelection = self.markedSelection.length != 0;
        NSString *translated = useLayout ? [_keyboard translateKey:code modifiers:flags] : nil;
        if (translated && self.hasEditingSession && replacingSelection) [self deleteSelection];
        if (translated && !translated.length) { [self notify]; return YES; }
        if (!translated) [self flushKeyboardPending];
        BOOL handled = [self processKey:code text:translated ?: text modifiers:flags layoutText:translated != nil];
        if (useLayout) [self notify];
        return handled;
    } @finally { [self endEdit]; }
}
- (void)flushKeyboardPending {
    NSString *text = [_keyboard takePendingText];
    if (!text.length) return;
    if (self.hasEditingSession) [self appendLiteral:text];
    else if (_committed) _committed(text);
}
- (BOOL)processKey:(NSUInteger)code text:(NSString *)text modifiers:(NSEventModifierFlags)flags layoutText:(BOOL)layoutText {
    if (!self.hasEditingSession) {
        _translationSourceLanguage = @"auto";
        _translationTargetLanguage = PairTranslationTarget(@"", self.inputLanguage);
    }
    // A Shift chord is not a tap; releasing it must not confirm a second time.
    _shiftCanConfirm = NO;
    BOOL composing = self.hasEditingSession;
    if (!composing) {
        _draftCloseSingleQuote = _closeSingleQuote;
        _draftCloseDoubleQuote = _closeDoubleQuote;
    }
    if (flags & NSEventModifierFlagCommand) return composing ? [self handleCommand:code modifiers:flags] : NO;
    if ((flags & NSEventModifierFlagControl) || ((flags & NSEventModifierFlagOption) && !layoutText)) {
        if (composing) [self cancel];
        return NO;
    }
    if (!InputLanguageUsesCandidates(_baseInputLanguage) && !composing) {
        // Let the host handle editing, navigation, shortcuts and function keys.
        if (!IsPrintableInput(text)) return NO;
        if (!layoutText && (flags & NSEventModifierFlagCapsLock)) {
            // Caps Lock selects a language here; Shift still selects uppercase letters.
            text = flags & NSEventModifierFlagShift ? text.uppercaseString : text.lowercaseString;
        }
        if (_committed) _committed(text);
        return YES;
    }
    if (composing && (flags & NSEventModifierFlagShift) && code >= 123 && code <= 126) {
        if (_engine.preedit.length) {
            [self clearSelection];
            [self moveCandidateHorizontally:code == 123 ? -1 : code == 124 ? 1 : 0 vertically:code == 126 ? -1 : code == 125 ? 1 : 0];
        } else [self moveTextCaret:code extending:YES];
        return YES;
    }
    if (self.markedSelection.length) {
        if (code == 53) { [self clearSelection]; _hint = L(@"Selection cleared · Draft preserved"); [self notify]; return YES; }
        if (code == 51 || code == 117) { [self deleteSelection]; [self notify]; return YES; }
        if (code == 115 || code == 119 ||
            ((code == 123 || code == 124) && !_engine.preedit.length)) {
            [self moveTextCaret:code];
            return YES;
        }
        if (code == 49) { [self deleteSelection]; [self appendLiteral:@" "]; return YES; }
        if (text.length == 1 && [text characterAtIndex:0] >= 0x21 && [text characterAtIndex:0] <= 0x7e)
            [self deleteSelection];
        else if ((code >= 123 && code <= 126) || code == 116 || code == 121) [self clearSelection];
    }
    if ((flags & NSEventModifierFlagShift) &&
        (code == 48 || code == 36 || code == 76 || (code >= 123 && code <= 126) ||
         code == 115 || code == 119 || code == 116 || code == 121)) {
        if (composing) [self cancel];
        return NO;
    }
    BOOL pending = _engine.preedit.length > 0;
    if (code == 53 && composing) {
        if (_candidatesExpanded) { [self collapseCandidates]; return YES; }
        if (pending) { [_engine clear]; [self notify]; }
        else [self cancel];
        return YES;
    }
    if (code == 48 && composing) { [self commitEnglish]; return YES; }
    if ((code == 36 || code == 76) && composing) {
        if (pending) [self confirmPendingLiteral]; else [self commitChinese];
        return YES;
    }
    if ((code == 51 || code == 117) && composing) {
        if (pending) [_engine processKey:code == 117 ? 0xffff : 0xff08];
        else [self deleteFromDraftForward:code == 117];
        [self collectCommit];
        return YES;
    }
    if (composing && (code == 115 || code == 119 ||
        ((code >= 123 && code <= 126) && !pending))) {
        [self moveTextCaret:code];
        return YES;
    }
    if ((code == 123 || code == 124 || code == 125 || code == 126 || code == 116 || code == 121) && composing) {
        if (pending) {
            if (code == 116 || code == 121) [self changeCandidatePage:code == 116];
            else [self moveCandidateHorizontally:code == 123 ? -1 : code == 124 ? 1 : 0 vertically:code == 126 ? -1 : code == 125 ? 1 : 0];
        }
        else { _hint = L(@"Arrows: move caret · Type to insert · Tab / Enter: commit"); [self notify]; }
        return YES;
    }
    if (code == 49 && composing) {
        if (pending) [self chooseCandidate:_engine.candidatePage.highlighted];
        else [self appendLiteral:@" "];
        return YES;
    }
    if (composing && !InputLanguageUsesCandidates(self.inputLanguage) && IsPrintableInput(text)) {
        if (!layoutText && (flags & NSEventModifierFlagCapsLock))
            text = flags & NSEventModifierFlagShift ? text.uppercaseString : text.lowercaseString;
        [self appendLiteral:text];
        return YES;
    }
    if (text.length != 1) return NO;
    unichar character = [text.lowercaseString characterAtIndex:0];
    if ((flags & NSEventModifierFlagShift) && character >= 'a' && character <= 'z') {
        if (pending) [self confirmPendingLiteral];
        [self appendLiteral:text.uppercaseString];
        return YES;
    }
    if ((character >= 'a' && character <= 'z') || (character == '\'' && pending) || (character == '-' && [self.inputLanguage isEqual:@"ja"] && !(flags & NSEventModifierFlagShift))) {
        [self clearSelection];
        BOOL accepted = [_engine processKey:character];
        [self collectCommit];
        return accepted;
    }
    if (pending && character >= '1' && character <= '9') {
        [self chooseCandidate:character - '1'];
        return YES;
    }
    if (character >= 0x21 && character <= 0x7e) {
        if (pending) { _hint = L(@"Confirm candidates before entering punctuation or numbers"); [self notify]; return YES; }
        [self appendLiteral:[self chinesePunctuation:text]];
        return YES;
    }
    if (composing) {
        _hint = L(@"Press Tab / Enter to insert, or Esc to cancel the draft");
        [self notify];
        return YES;
    }
    return NO;
}
@end
