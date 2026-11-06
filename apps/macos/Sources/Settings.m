#import "Core.h"
#import "SelectionTranslation.h"
#import "ModelProvider.h"
#import "KeyboardLayoutEngine.h"
#import "SettingsController.h"

NSInteger ReadCandidateColumns(void) {
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:@"candidateColumns"];
    return value >= MinimumCandidateColumns && value <= MaximumCandidateColumns ? value : DefaultCandidateColumns;
}

BOOL ReadLearningEnabled(void) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:@"learningEnabled"];
    return value ? [value boolValue] : YES;
}

NSArray<NSString *> *DecodeOllamaModels(NSData *data, NSError **error) {
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![json isKindOfClass:NSDictionary.class] || ![json[@"models"] isKindOfClass:NSArray.class]) {
        if (error) *error = [NSError errorWithDomain:@"DualLineIME" code:2 userInfo:@{NSLocalizedDescriptionKey:L(@"Ollama returned an invalid model list")}];
        return nil;
    }
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    for (id entry in json[@"models"]) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        id name = entry[@"name"];
        if (![name isKindOfClass:NSString.class]) continue;
        NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (trimmed.length) [names addObject:trimmed];
    }
    return [[names allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

static void AddLanguageItem(NSPopUpButton *popup, NSString *title, NSString *code) {
    [popup addItemWithTitle:title];
    popup.lastItem.representedObject = code;
}
static void SelectLanguageItem(NSPopUpButton *popup, NSString *code) {
    NSInteger index = [popup indexOfItemWithRepresentedObject:code];
    [popup selectItemAtIndex:index == -1 ? 0 : index];
}

@implementation ModelSettingsController {
    NSUserDefaults *_preferences;
    id _preferencesObserver;
    ModelPreferencesView *_modelPreferences;
    NSPopUpButton *_columns;
    NSButton *_learning;
    NSButton *_selectionEnabled;
    NSButton *_selectionAutomatic;
    NSPopUpButton *_firstLanguage;
    NSPopUpButton *_secondLanguage;
    NSTextField *_firstTypingMethod;
    NSTextField *_secondTypingMethod;
    NSString *_previousFirstLanguage;
    NSString *_previousSecondLanguage;
    NSPopUpButton *_interfaceLanguage;
    NSTextField *_selectionDirection;
    NSTextField *_permissionStatus;
    NSTextView *_translationPrompt;
    NSTimer *_permissionTimer;
    NSButton *_save;
    NSRunningApplication *_previousApp;
}
- (NSTextField *)label:(NSString *)text size:(CGFloat)size {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:size];
    return label;
}
- (instancetype)init {
    return [self initWithPreferences:NSUserDefaults.standardUserDefaults];
}
- (instancetype)initWithPreferences:(NSUserDefaults *)preferences {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 660, 740) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    if ((self = [super initWithWindow:window])) {
        _preferences = preferences;
        window.title = L(@"{appName} Settings");
        window.releasedWhenClosed = NO;
        window.delegate = self;
        NSTextField *candidateTitle = [self label:L(@"Candidates") size:17];
        candidateTitle.font = [NSFont boldSystemFontOfSize:17];
        _columns = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        for (NSInteger count = MinimumCandidateColumns; count <= MaximumCandidateColumns; count++) {
            [_columns addItemWithTitle:[NSString stringWithFormat:L(@"%ld"), (long)count]];
            _columns.lastItem.tag = count;
        }
        _columns.target = self;
        _columns.action = @selector(selectionChanged:);
        NSStackView *candidateRow = [NSStackView stackViewWithViews:@[[self label:L(@"Candidates per row") size:13], _columns]];
        candidateRow.spacing = 12;
        NSTextField *candidateNote = [self label:L(@"Default: 5 per row. Press ↓ to expand to multiple rows.\nSaved changes apply to the next composition.") size:12];
        candidateNote.textColor = NSColor.secondaryLabelColor;
        _learning = [NSButton checkboxWithTitle:L(@"Learn frequently used words and phrases") target:self action:@selector(selectionChanged:)];
        NSTextField *learningNote = [self label:L(@"Rank Chinese and Japanese candidates using the words you confirm, including after restarting.\nLearning stays on this device. Turning it off uses the base ranking and preserves existing learning.\nSaved changes apply to the next composition.") size:12];
        learningNote.textColor = NSColor.secondaryLabelColor;
        NSTextField *note = [self label:L(@"Space / numbers: choose · Tab: translation · Enter: source") size:12];
        note.textColor = NSColor.secondaryLabelColor;
        NSTextField *modeNote = [self label:L(@"Caps Lock controls the input language: off uses the first language, on uses the second. Switching while composing confirms the highlighted candidate, inserts the source sentence, then changes language. There is no temporary language mode.") size:12];
        modeNote.textColor = NSColor.secondaryLabelColor;
        _save = [NSButton buttonWithTitle:L(@"Save") target:self action:@selector(save:)];
        _save.keyEquivalent = @"\r";
        NSButton *cancel = [NSButton buttonWithTitle:L(@"Cancel") target:self action:@selector(cancel:)];
        cancel.keyEquivalent = @"\e";
        NSStackView *actions = [NSStackView stackViewWithViews:@[cancel, _save]];
        actions.spacing = 10;
        NSTabView *tabs = [NSTabView new];
        tabs.translatesAutoresizingMaskIntoConstraints = NO;
        [window.contentView addSubview:tabs];
        _modelPreferences = [ModelPreferencesView new];
        NSTabViewItem *modelTab = [[NSTabViewItem alloc] initWithIdentifier:@"models"];
        modelTab.label = L(@"Models");
        modelTab.view = _modelPreferences;
        [tabs addTabViewItem:modelTab];
        NSView *inputView = [NSView new];
        NSTabViewItem *inputTab = [[NSTabViewItem alloc] initWithIdentifier:@"input"];
        inputTab.label = L(@"Input");
        inputTab.view = inputView;
        [tabs addTabViewItem:inputTab];
        NSStackView *stack = [NSStackView stackViewWithViews:@[candidateTitle, candidateRow, candidateNote, _learning, learningNote, note, modeNote]];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 16;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [inputView addSubview:stack];
        actions.translatesAutoresizingMaskIntoConstraints = NO;
        [window.contentView addSubview:actions];
        [NSLayoutConstraint activateConstraints:@[
            [tabs.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:16],
            [tabs.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-16],
            [tabs.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:14],
            [tabs.bottomAnchor constraintEqualToAnchor:actions.topAnchor constant:-14],
            [actions.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-24],
            [actions.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor constant:-18],
            [stack.leadingAnchor constraintEqualToAnchor:inputView.leadingAnchor constant:12],
            [stack.trailingAnchor constraintEqualToAnchor:inputView.trailingAnchor constant:-12],
            [stack.topAnchor constraintEqualToAnchor:inputView.topAnchor constant:14],
            [stack.bottomAnchor constraintLessThanOrEqualToAnchor:inputView.bottomAnchor constant:-14],
            [learningNote.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
            [note.widthAnchor constraintEqualToAnchor:stack.widthAnchor]
        ]];
        [modeNote.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        NSView *languageView = [NSView new];
        NSTabViewItem *languageTab = [[NSTabViewItem alloc] initWithIdentifier:@"languages"];
        languageTab.label = L(@"Languages");
        languageTab.view = languageView;
        [tabs addTabViewItem:languageTab];
        NSTextField *languageTitle = [self label:L(@"Your language pair") size:20];
        languageTitle.font = [NSFont boldSystemFontOfSize:20];
        _firstLanguage = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        _secondLanguage = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        _firstLanguage.target = _secondLanguage.target = self;
        _firstLanguage.action = _secondLanguage.action = @selector(translationDirectionChanged:);
        _firstLanguage.accessibilityLabel = L(@"First language");
        _secondLanguage.accessibilityLabel = L(@"Second language");
        for (NSString *code in InputLanguages()) {
            AddLanguageItem(_firstLanguage, TranslationLanguageName(code), code);
            AddLanguageItem(_secondLanguage, TranslationLanguageName(code), code);
        }
        NSTextField *fromLabel = [self label:L(@"First language") size:13];
        NSTextField *toLabel = [self label:L(@"Second language") size:13];
        NSStackView *fromRow = [NSStackView stackViewWithViews:@[fromLabel, _firstLanguage]];
        NSStackView *toRow = [NSStackView stackViewWithViews:@[toLabel, _secondLanguage]];
        fromRow.spacing = toRow.spacing = 14;
        _firstTypingMethod = [self label:@"" size:12];
        _secondTypingMethod = [self label:@"" size:12];
        _firstTypingMethod.textColor = _secondTypingMethod.textColor = NSColor.secondaryLabelColor;
        NSTextField *languageNote = [self label:L(@"Caps Lock off: first language. Caps Lock on: second language. The input menu only shows the current language; use the keyboard to switch.") size:13];
        NSTextField *languageUsage = [self label:L(@"Text in either language is translated into the other. Mixed text uses its dominant language; uncertain selections translate into the first language.\n\nChinese uses pinyin. Japanese uses romaji with kana and kanji candidates. Other available keyboards use their native layout. Korean typing is not available yet; Korean translation is supported.\n\nSave to apply. The active language follows Caps Lock, including after changing this pair.") size:12];
        languageUsage.textColor = NSColor.secondaryLabelColor;
        NSStackView *languageStack = [NSStackView stackViewWithViews:@[languageTitle, fromRow, _firstTypingMethod, toRow, _secondTypingMethod, languageNote, languageUsage]];
        languageStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        languageStack.alignment = NSLayoutAttributeLeading;
        languageStack.spacing = 20;
        languageStack.translatesAutoresizingMaskIntoConstraints = NO;
        [languageView addSubview:languageStack];
        [NSLayoutConstraint activateConstraints:@[
            [languageStack.leadingAnchor constraintEqualToAnchor:languageView.leadingAnchor constant:12],
            [languageStack.trailingAnchor constraintEqualToAnchor:languageView.trailingAnchor constant:-12],
            [languageStack.topAnchor constraintEqualToAnchor:languageView.topAnchor constant:18],
            [languageStack.bottomAnchor constraintLessThanOrEqualToAnchor:languageView.bottomAnchor constant:-14],
            [fromLabel.widthAnchor constraintEqualToConstant:130],
            [toLabel.widthAnchor constraintEqualToConstant:130],
            [_firstLanguage.widthAnchor constraintEqualToConstant:300],
            [_secondLanguage.widthAnchor constraintEqualToConstant:300],
            [_firstTypingMethod.widthAnchor constraintEqualToAnchor:languageStack.widthAnchor],
            [_secondTypingMethod.widthAnchor constraintEqualToAnchor:languageStack.widthAnchor],
            [languageNote.widthAnchor constraintEqualToAnchor:languageStack.widthAnchor],
            [languageUsage.widthAnchor constraintEqualToAnchor:languageStack.widthAnchor]
        ]];

        NSView *selectionView = [NSView new];
        NSTabViewItem *selectionTab = [[NSTabViewItem alloc] initWithIdentifier:@"selection"];
        selectionTab.label = L(@"Selection");
        selectionTab.view = selectionView;
        [tabs addTabViewItem:selectionTab];
        NSTextField *selectionTitle = [self label:L(@"Select text to translate") size:20];
        selectionTitle.font = [NSFont boldSystemFontOfSize:20];
        _selectionEnabled = [NSButton checkboxWithTitle:L(@"Enable selection translation") target:self action:@selector(selectionPreferenceChanged:)];
        _selectionAutomatic = [NSButton checkboxWithTitle:L(@"Show translations automatically after selecting text") target:self action:@selector(selectionPreferenceChanged:)];
        NSTextField *selectionApplyNote = [self label:L(@"These two switches apply immediately. Save and Cancel affect the other settings.") size:12];
        selectionApplyNote.textColor = NSColor.secondaryLabelColor;
        _selectionDirection = [self label:@"" size:13];
        NSTextField *selectionNote = [self label:L(@"Both input translation and selection translation detect which language in your pair the text uses, then translate into the other. The selected input mode does not force the translation direction.\n\nAutomatic display is off by default. Enable it to show the translation as soon as the selection settles; otherwise click the Translate button.\n\nCopy from the top right; click outside to close. Select again to retry. The source text is never replaced.") size:13];
        _permissionStatus = [self label:@"" size:13];
        NSButton *permission = [NSButton buttonWithTitle:L(@"Open Accessibility Settings…") target:self action:@selector(openSelectionPermission:)];
        NSTextField *permissionNote = [self label:L(@"Enable Accessibility permission for {appName} to read selections in other apps. Typing itself does not need this permission.\n\nIf the selection position is unavailable, the popup appears beside the pointer once and stays there. Text in images is not supported.") size:12];
        permissionNote.textColor = NSColor.secondaryLabelColor;
        NSStackView *selectionStack = [NSStackView stackViewWithViews:@[selectionTitle, _selectionEnabled, _selectionAutomatic, selectionApplyNote, _selectionDirection, selectionNote, _permissionStatus, permission, permissionNote]];
        selectionStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        selectionStack.alignment = NSLayoutAttributeLeading;
        selectionStack.spacing = 14;
        selectionStack.translatesAutoresizingMaskIntoConstraints = NO;
        [selectionView addSubview:selectionStack];
        [NSLayoutConstraint activateConstraints:@[
            [selectionStack.leadingAnchor constraintEqualToAnchor:selectionView.leadingAnchor constant:12],
            [selectionStack.trailingAnchor constraintEqualToAnchor:selectionView.trailingAnchor constant:-12],
            [selectionStack.topAnchor constraintEqualToAnchor:selectionView.topAnchor constant:18],
            [_selectionDirection.widthAnchor constraintEqualToAnchor:selectionStack.widthAnchor],
            [selectionNote.widthAnchor constraintEqualToAnchor:selectionStack.widthAnchor],
            [permissionNote.widthAnchor constraintEqualToAnchor:selectionStack.widthAnchor],
            [selectionApplyNote.widthAnchor constraintEqualToAnchor:selectionStack.widthAnchor]
        ]];

        NSView *promptView = [NSView new];
        NSTabViewItem *promptTab = [[NSTabViewItem alloc] initWithIdentifier:@"prompt"];
        promptTab.label = L(@"Prompt");
        promptTab.view = promptView;
        [tabs addTabViewItem:promptTab];
        NSTextField *promptTitle = [self label:L(@"Translation instructions") size:20];
        promptTitle.font = [NSFont boldSystemFontOfSize:20];
        NSTextField *promptDescription = [self label:L(@"Shared by composition and selection translation. Write instructions in Chinese or English.\nTranslation direction and rules for preserving lines, blank lines, indentation, and lists are added automatically.") size:13];
        NSScrollView *promptScroll = [NSScrollView new];
        promptScroll.hasVerticalScroller = YES;
        promptScroll.autohidesScrollers = YES;
        promptScroll.borderType = NSBezelBorder;
        _translationPrompt = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 480, 300)];
        _translationPrompt.richText = NO;
        _translationPrompt.allowsUndo = YES;
        _translationPrompt.font = [NSFont systemFontOfSize:13];
        _translationPrompt.textColor = NSColor.textColor;
        _translationPrompt.backgroundColor = NSColor.textBackgroundColor;
        _translationPrompt.textContainerInset = NSMakeSize(8, 8);
        _translationPrompt.verticallyResizable = YES;
        _translationPrompt.horizontallyResizable = NO;
        _translationPrompt.autoresizingMask = NSViewWidthSizable;
        _translationPrompt.textContainer.widthTracksTextView = YES;
        _translationPrompt.automaticQuoteSubstitutionEnabled = NO;
        _translationPrompt.automaticDashSubstitutionEnabled = NO;
        _translationPrompt.automaticTextReplacementEnabled = NO;
        _translationPrompt.automaticSpellingCorrectionEnabled = NO;
        _translationPrompt.accessibilityLabel = L(@"Prompt");
        promptScroll.documentView = _translationPrompt;
        NSButton *restorePrompt = [NSButton buttonWithTitle:L(@"Restore default prompt") target:self action:@selector(restoreTranslationPrompt:)];
        NSTextField *promptNote = [self label:L(@"Saved changes apply to the next translation. Cancel discards changes.\nSave after restoring defaults. Saving an empty prompt also uses the default.") size:12];
        promptNote.textColor = NSColor.secondaryLabelColor;
        NSStackView *promptStack = [NSStackView stackViewWithViews:@[promptTitle, promptDescription, promptScroll, restorePrompt, promptNote]];
        promptStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        promptStack.alignment = NSLayoutAttributeLeading;
        promptStack.spacing = 14;
        promptStack.translatesAutoresizingMaskIntoConstraints = NO;
        [promptView addSubview:promptStack];
        [NSLayoutConstraint activateConstraints:@[
            [promptStack.leadingAnchor constraintEqualToAnchor:promptView.leadingAnchor constant:12],
            [promptStack.trailingAnchor constraintEqualToAnchor:promptView.trailingAnchor constant:-12],
            [promptStack.topAnchor constraintEqualToAnchor:promptView.topAnchor constant:18],
            [promptStack.bottomAnchor constraintEqualToAnchor:promptView.bottomAnchor constant:-14],
            [promptDescription.widthAnchor constraintEqualToAnchor:promptStack.widthAnchor],
            [promptScroll.widthAnchor constraintEqualToAnchor:promptStack.widthAnchor],
            [promptScroll.heightAnchor constraintGreaterThanOrEqualToConstant:240],
            [promptNote.widthAnchor constraintEqualToAnchor:promptStack.widthAnchor]
        ]];

        NSView *generalView = [NSView new];
        NSTabViewItem *generalTab = [[NSTabViewItem alloc] initWithIdentifier:@"general"];
        generalTab.label = L(@"General");
        generalTab.view = generalView;
        [tabs addTabViewItem:generalTab];
        NSTextField *interfaceTitle = [self label:L(@"Interface language") size:20];
        interfaceTitle.font = [NSFont boldSystemFontOfSize:20];
        _interfaceLanguage = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        _interfaceLanguage.accessibilityLabel = L(@"Interface language");
        AddLanguageItem(_interfaceLanguage, L(@"Follow System"), @"system");
        AddLanguageItem(_interfaceLanguage, @"English", @"en");
        AddLanguageItem(_interfaceLanguage, @"简体中文", @"zh-Hans");
        NSTextField *interfaceNote = [self label:L(@"The interface supports English and Simplified Chinese. It follows the system by default, with English as the fallback. After saving, reopen Settings to update this window. New composition and selection panels use the chosen language.\n\nThis changes only the interface, not translation direction, keyboard mode, or the dictionary.") size:13];
        interfaceNote.textColor = NSColor.secondaryLabelColor;
        NSStackView *generalStack = [NSStackView stackViewWithViews:@[interfaceTitle, _interfaceLanguage, interfaceNote]];
        generalStack.orientation = NSUserInterfaceLayoutOrientationVertical;
        generalStack.alignment = NSLayoutAttributeLeading;
        generalStack.spacing = 20;
        generalStack.translatesAutoresizingMaskIntoConstraints = NO;
        [generalView addSubview:generalStack];
        [NSLayoutConstraint activateConstraints:@[
            [generalStack.leadingAnchor constraintEqualToAnchor:generalView.leadingAnchor constant:12],
            [generalStack.trailingAnchor constraintEqualToAnchor:generalView.trailingAnchor constant:-12],
            [generalStack.topAnchor constraintEqualToAnchor:generalView.topAnchor constant:18],
            [_interfaceLanguage.widthAnchor constraintEqualToConstant:300],
            [interfaceNote.widthAnchor constraintEqualToAnchor:generalStack.widthAnchor]
        ]];
        [self refreshSelectionPreferences];
        __weak ModelSettingsController *weakSelf = self;
        _preferencesObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            [weakSelf refreshSelectionPreferences];
        }];
    }
    return self;
}
- (void)present {
    if (!self.window.visible) {
        _previousApp = NSWorkspace.sharedWorkspace.frontmostApplication;
        [_modelPreferences loadPreferences];
        SelectLanguageItem(_interfaceLanguage, ReadInterfaceLanguage());
        [_columns selectItemWithTag:ReadCandidateColumns()];
        _learning.state = ReadLearningEnabled() ? NSControlStateValueOn : NSControlStateValueOff;
        _translationPrompt.string = ReadTranslationPrompt();
        [_translationPrompt.undoManager removeAllActions];
        [_translationPrompt scrollRangeToVisible:NSMakeRange(0, 0)];
        SelectLanguageItem(_firstLanguage, ReadFirstInputLanguage());
        SelectLanguageItem(_secondLanguage, ReadSecondInputLanguage());
        [self translationDirectionChanged:nil];
        [self.window center];
    }
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self updateSelectionPermission];
    if (!_permissionTimer) {
        __weak ModelSettingsController *weakSelf = self;
        _permissionTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf updateSelectionPermission]; }];
    }
}
- (void)updateSelectionPermission {
    // The existing timer also catches changes made by another process.
    [self refreshSelectionPreferences];
    _permissionStatus.stringValue = SelectionTranslationHasPermission() ? L(@"Accessibility permission enabled") : L(@"Permission required for selection translation");
    [self translationDirectionChanged:nil];
}
- (void)refreshSelectionPreferences {
    id enabled = [_preferences objectForKey:@"selectionTranslationEnabled"];
    id automatic = [_preferences objectForKey:@"selectionTranslationAutomatic"];
    _selectionEnabled.state = (!enabled || [enabled boolValue]) ? NSControlStateValueOn : NSControlStateValueOff;
    _selectionAutomatic.state = ([automatic isKindOfClass:NSNumber.class] && [automatic boolValue]) ? NSControlStateValueOn : NSControlStateValueOff;
}
- (void)selectionPreferenceChanged:(NSButton *)sender {
    // Write only the changed switch; the other one may have changed in the popup.
    NSString *key = sender == _selectionEnabled ? @"selectionTranslationEnabled" : @"selectionTranslationAutomatic";
    [_preferences setBool:sender.state == NSControlStateValueOn forKey:key];
    [self refreshSelectionPreferences];
}
- (void)translationDirectionChanged:(id)sender {
    NSString *first = _firstLanguage.selectedItem.representedObject;
    NSString *second = _secondLanguage.selectedItem.representedObject;
    if ([first isEqual:second]) {
        NSPopUpButton *other = sender == _secondLanguage ? _firstLanguage : _secondLanguage;
        NSString *previous = sender == _secondLanguage ? _previousSecondLanguage : _previousFirstLanguage;
        if (!previous || [previous isEqual:first])
            previous = [first isEqual:@"en"] ? @"zh" : @"en";
        SelectLanguageItem(other, previous);
    }
    _previousFirstLanguage = _firstLanguage.selectedItem.representedObject;
    _previousSecondLanguage = _secondLanguage.selectedItem.representedObject;
    _firstTypingMethod.stringValue = InputLanguageTypingMethod(_previousFirstLanguage);
    _secondTypingMethod.stringValue = InputLanguageTypingMethod(_previousSecondLanguage);
    _selectionDirection.stringValue = [NSString stringWithFormat:L(@"Language pair: %@ ↔ %@ · automatic direction"),
        TranslationLanguageName(_firstLanguage.selectedItem.representedObject), TranslationLanguageName(_secondLanguage.selectedItem.representedObject)];
}
- (void)openSelectionPermission:(id)sender { RequestSelectionTranslationPermission(); }
- (void)restoreTranslationPrompt:(id)sender {
    _translationPrompt.string = DefaultTranslationPrompt();
    [_translationPrompt.undoManager removeAllActions];
    [_translationPrompt scrollRangeToVisible:NSMakeRange(0, 0)];
}
- (void)selectionChanged:(id)sender { _save.enabled = YES; }
- (BOOL)savePreferences:(NSError **)error {
    if (![_modelPreferences savePreferences:error]) return NO;
    [_preferences setInteger:_columns.selectedItem.tag forKey:@"candidateColumns"];
    [_preferences setBool:_learning.state == NSControlStateValueOn forKey:@"learningEnabled"];
    // Selection switches are already saved. Never overwrite them from stale controls.
    [_preferences setObject:_firstLanguage.selectedItem.representedObject forKey:@"firstInputLanguage"];
    [_preferences setObject:_secondLanguage.selectedItem.representedObject forKey:@"secondInputLanguage"];
    [_preferences setObject:_interfaceLanguage.selectedItem.representedObject forKey:@"interfaceLanguage"];
    NSString *prompt = [_translationPrompt.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!prompt.length || [prompt isEqual:DefaultTranslationPrompt()])
        [_preferences removeObjectForKey:@"translationPrompt"];
    else
        [_preferences setObject:prompt forKey:@"translationPrompt"];
    [self refreshSelectionPreferences];
    return YES;
}
- (void)save:(id)sender {
    NSError *error;
    if (![self savePreferences:&error]) {
        NSAlert *alert = [NSAlert new];
        alert.messageText = L(@"Model settings not saved");
        alert.informativeText = error.localizedDescription ?: L(@"Check the model settings.");
        [alert addButtonWithTitle:L(@"OK")];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }
    [self close];
    if (_previousApp.processIdentifier != NSProcessInfo.processInfo.processIdentifier) [_previousApp activateWithOptions:0];
}
- (void)cancel:(id)sender {
    [self close];
    if (_previousApp.processIdentifier != NSProcessInfo.processInfo.processIdentifier) [_previousApp activateWithOptions:0];
}
- (void)windowWillClose:(NSNotification *)notification {
    [_modelPreferences cancelPending];
    [_permissionTimer invalidate];
    _permissionTimer = nil;
}
- (void)dealloc {
    if (_preferencesObserver) [NSNotificationCenter.defaultCenter removeObserver:_preferencesObserver];
}
@end

void ShowSettings(void) {
    static ModelSettingsController *settings;
    // Rebuild closed settings so both app and system language changes are reflected.
    if (!settings.window.visible) settings = [ModelSettingsController new];
    [settings present];
}
