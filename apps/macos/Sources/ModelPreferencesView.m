#import "ModelProvider.h"

static NSTextField *ModelLabel(NSString *text, CGFloat size) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.font = [NSFont systemFontOfSize:size];
    return label;
}
static NSStackView *ModelStack(NSArray<NSView *> *views) {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.detachesHiddenViews = YES;
    return stack;
}
static NSStackView *ModelRow(NSString *title, NSView *control, NSView *extra) {
    NSTextField *label = ModelLabel(title, 13);
    [label.widthAnchor constraintEqualToConstant:90].active = YES;
    NSStackView *row = [NSStackView stackViewWithViews:extra ? @[label, control, extra] : @[label, control]];
    row.spacing = 8;
    row.alignment = NSLayoutAttributeCenterY;
    [control setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return row;
}

@interface ModelPreferencesView () <NSTextFieldDelegate, NSComboBoxDelegate>
@end
@implementation ModelPreferencesView {
    NSPopUpButton *_provider, *_localModels, *_reasoning;
    NSComboBox *_onlineModel;
    NSTextField *_baseURL, *_status, *_keyStatus, *_reasoningNote;
    NSSecureTextField *_apiKey;
    NSStackView *_localStack, *_onlineStack;
    NSButton *_refreshLocal, *_refreshOnline;
    NSString *_originalLocalModel, *_keyEndpoint;
    NSArray<NSString *> *_availableLocal;
    NSURLSessionDataTask *_request;
    NSUInteger _generation;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        NSTextField *title = ModelLabel(L(@"Translation model"), 20);
        title.font = [NSFont boldSystemFontOfSize:20];
        _provider = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [_provider addItemsWithTitles:@[L(@"Local Ollama"), L(@"Online · OpenAI-compatible")]];
        _provider.target = self; _provider.action = @selector(providerChanged:);
        _provider.accessibilityLabel = L(@"Provider");
        NSStackView *providerRow = ModelRow(L(@"Provider"), _provider, nil);
        _localModels = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        _localModels.accessibilityLabel = L(@"Ollama model");
        _refreshLocal = [NSButton buttonWithTitle:L(@"Refresh models") target:self action:@selector(refreshLocal:)];
        NSStackView *localRow = ModelRow(L(@"Local model"), _localModels, _refreshLocal);
        NSTextField *localNote = ModelLabel(L(@"Choose an installed model. Downloading a model does not select it automatically. Save to apply."), 12);
        localNote.textColor = NSColor.secondaryLabelColor;
        _localStack = ModelStack(@[localRow, localNote]);

        _baseURL = [NSTextField textFieldWithString:@""];
        _baseURL.placeholderString = @"https://api.openai.com/v1";
        _baseURL.accessibilityLabel = L(@"API URL");
        _baseURL.delegate = self;
        _apiKey = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
        _apiKey.placeholderString = L(@"Enter API key; leave blank to keep the saved key");
        _apiKey.accessibilityLabel = @"API Key";
        _keyStatus = ModelLabel(L(@"API keys are stored in your local Keychain, separately for each API URL."), 12);
        _keyStatus.textColor = NSColor.secondaryLabelColor;
        _onlineModel = [[NSComboBox alloc] initWithFrame:NSZeroRect];
        _onlineModel.placeholderString = L(@"Enter a model ID or refresh to choose one");
        _onlineModel.completes = NO;
        _onlineModel.numberOfVisibleItems = 10;
        _onlineModel.delegate = self;
        _onlineModel.accessibilityLabel = L(@"Online model ID");
        _refreshOnline = [NSButton buttonWithTitle:L(@"Refresh list") target:self action:@selector(refreshOnline:)];
        _reasoning = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [_reasoning addItemsWithTitles:@[L(@"Lowest (recommended)"), L(@"Service default"), L(@"None · none"), L(@"Minimal · minimal"), L(@"Low · low"), L(@"Medium · medium"), L(@"High · high"), L(@"Extra high · xhigh"), L(@"Maximum · max")]];
        _reasoning.target = self; _reasoning.action = @selector(reasoningChanged:);
        _reasoning.accessibilityLabel = L(@"Model reasoning effort");
        _reasoningNote = ModelLabel(@"", 12);
        _reasoningNote.textColor = NSColor.secondaryLabelColor;
        NSTextField *onlineNote = ModelLabel(L(@"Online mode sends your draft or selected text to this API URL. Provider charges may apply. Refreshing the list only fetches models; it does not send your text.\nInclude the required API prefix, such as /v1."), 12);
        onlineNote.textColor = NSColor.secondaryLabelColor;
        _onlineStack = ModelStack(@[ModelRow(L(@"API URL"), _baseURL, nil), ModelRow(@"API Key", _apiKey, nil), _keyStatus,
                                   ModelRow(L(@"Model ID"), _onlineModel, _refreshOnline), ModelRow(L(@"Reasoning"), _reasoning, nil), _reasoningNote, onlineNote]);
        _status = ModelLabel(@"", 12);
        _status.textColor = NSColor.secondaryLabelColor;
        NSTextField *note = ModelLabel(L(@"Composition and selection translation share this model. Saved changes apply to the next request."), 12);
        note.textColor = NSColor.secondaryLabelColor;
        NSStackView *stack = ModelStack(@[title, providerRow, _localStack, _onlineStack, _status, note]);
        stack.spacing = 16;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:18],
            [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-12]
        ]];
        for (NSView *view in @[providerRow, _localStack, _onlineStack, _status, note])
            [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        for (NSStackView *group in @[_localStack, _onlineStack])
            for (NSView *view in group.arrangedSubviews) [view.widthAnchor constraintEqualToAnchor:group.widthAnchor].active = YES;
    }
    return self;
}
- (BOOL)online { return _provider.indexOfSelectedItem == 1; }
- (NSString *)reasoning { return OnlineReasoningOptions()[_reasoning.indexOfSelectedItem]; }
- (void)loadPreferences {
    [self cancelPending];
    _originalLocalModel = [NSUserDefaults.standardUserDefaults stringForKey:@"model"] ?: @"qwen2.5:3b";
    [_localModels removeAllItems]; [_localModels addItemWithTitle:_originalLocalModel];
    _availableLocal = nil;
    _baseURL.stringValue = ReadOnlineBaseURL();
    _keyEndpoint = NormalizeOnlineBaseURL(_baseURL.stringValue, NULL);
    [_onlineModel removeAllItems];
    _onlineModel.stringValue = ReadOnlineModel();
    [_reasoning selectItemAtIndex:[OnlineReasoningOptions() indexOfObject:ReadOnlineReasoning()]];
    [_provider selectItemAtIndex:UsesOnlineTranslation() ? 1 : 0];
    [self providerChanged:nil];
    [self updateKeyStatus];
    [self reasoningChanged:nil];
}
- (void)providerChanged:(id)sender {
    [_request cancel]; ++_generation;
    _refreshLocal.enabled = _refreshOnline.enabled = YES;
    _localModels.enabled = YES;
    _localStack.hidden = self.online;
    _onlineStack.hidden = !self.online;
    _status.stringValue = self.online ? L(@"You can enter a model ID manually even if the model list is unavailable.") : @"";
    if (!self.online && !_availableLocal) [self refreshLocal:nil];
}
- (void)updateKeyStatus {
    BOOL saved = _keyEndpoint && HasOnlineAPIKey(_keyEndpoint);
    _keyStatus.stringValue = saved ? L(@"A key is saved for this URL in Keychain. Leave blank to keep it, or enter a replacement.") : L(@"No key is saved for this URL. Keys are stored only in your local Keychain.");
}
- (void)reasoningChanged:(id)sender { _reasoningNote.stringValue = OnlineReasoningExplanation(_onlineModel.stringValue, self.reasoning); }
- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == _baseURL) {
        NSString *endpoint = NormalizeOnlineBaseURL(_baseURL.stringValue, NULL);
        if (![_keyEndpoint isEqual:endpoint]) {
            _apiKey.stringValue = @""; // Never carry a typed credential to a different endpoint.
            _keyEndpoint = endpoint;
            [_request cancel]; ++_generation; _refreshOnline.enabled = YES;
            [_onlineModel removeAllItems];
            [self updateKeyStatus];
        }
    }
    [self reasoningChanged:nil];
}
- (void)comboBoxSelectionDidChange:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{ [self reasoningChanged:nil]; });
}
- (NSString *)currentKey:(NSString *)endpoint error:(NSError **)error {
    NSString *typed = [_apiKey.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return typed.length ? typed : ReadOnlineAPIKey(endpoint, YES, error);
}
- (void)refreshLocal:(id)sender {
    [_request cancel]; NSUInteger generation = ++_generation;
    NSString *current = _localModels.titleOfSelectedItem ?: _originalLocalModel;
    _refreshLocal.enabled = NO;
    _status.stringValue = L(@"Loading local Ollama models…");
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"http://127.0.0.1:11434/api/tags"] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5];
    __weak ModelPreferencesView *weakSelf = self;
    _request = [ModelProviderSession() dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        NSArray *names = !error && status == 200 && data ? DecodeOllamaModels(data, NULL) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            ModelPreferencesView *self = weakSelf;
            if (!self || self->_generation != generation) return;
            self->_refreshLocal.enabled = YES;
            if (!names) { self->_status.stringValue = L(@"Could not load Ollama models. Your current model is unchanged; other settings can still be saved."); return; }
            self->_availableLocal = names;
            [self->_localModels removeAllItems];
            if (![names containsObject:current]) [self->_localModels addItemWithTitle:current];
            [self->_localModels addItemsWithTitles:names];
            [self->_localModels selectItemWithTitle:current];
            self->_status.stringValue = [NSString stringWithFormat:L(@"Connected to Ollama · %lu installed models%@"), (unsigned long)names.count, [names containsObject:current] ? @"" : L(@"; the current model is not installed")];
        });
    }];
    [_request resume];
}
- (void)refreshOnline:(id)sender {
    NSError *error;
    NSString *endpoint = NormalizeOnlineBaseURL(_baseURL.stringValue, &error);
    NSString *key = endpoint ? [self currentKey:endpoint error:&error] : nil;
    NSURLRequest *request = key ? MakeOnlineModelsRequest(endpoint, key, &error) : nil;
    if (!request) { _status.stringValue = error.localizedDescription ?: L(@"Enter an API key."); return; }
    [_request cancel]; NSUInteger generation = ++_generation;
    _refreshOnline.enabled = NO;
    _status.stringValue = L(@"Loading online models…");
    __weak ModelPreferencesView *weakSelf = self;
    _request = [ModelProviderSession() dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        NSError *parseError;
        NSArray *names = !networkError && status == 200 ? DecodeOnlineModels(data, &parseError) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            ModelPreferencesView *self = weakSelf;
            if (!self || self->_generation != generation) return;
            self->_refreshOnline.enabled = YES;
            if (!names) { self->_status.stringValue = (parseError ?: TranslationRequestError(status, YES)).localizedDescription; return; }
            NSString *current = self->_onlineModel.stringValue;
            [self->_onlineModel removeAllItems]; [self->_onlineModel addItemsWithObjectValues:names];
            self->_onlineModel.stringValue = current;
            self->_status.stringValue = [NSString stringWithFormat:L(@"Loaded %lu models. Choose one that supports text chat."), (unsigned long)names.count];
        });
    }];
    [_request resume];
}
- (BOOL)savePreferences:(NSError **)error {
    NSUserDefaults *preferences = NSUserDefaults.standardUserDefaults;
    if (self.online) {
        NSString *endpoint = NormalizeOnlineBaseURL(_baseURL.stringValue, error);
        NSString *model = [_onlineModel.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!endpoint) return NO;
        if (!ValidOnlineModel(model)) { if (error) *error = ModelProviderError(3, L(@"Enter an online model ID in Models.")); return NO; }
        NSString *key = [_apiKey.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (key.length) {
            if (!MakeOnlineModelsRequest(endpoint, key, error) || !SaveOnlineAPIKey(endpoint, key, error)) return NO;
        } else if (!HasOnlineAPIKey(endpoint)) {
            if (error) *error = ModelProviderError(2, L(@"Enter the API key for this URL in Models.")); return NO;
        }
        [preferences setObject:endpoint forKey:@"onlineBaseURL"];
        [preferences setObject:model forKey:@"onlineModel"];
        [preferences setObject:self.reasoning forKey:@"onlineReasoning"];
    } else {
        NSString *model = _localModels.titleOfSelectedItem;
        if (![model isEqual:_originalLocalModel] && ![_availableLocal containsObject:model]) {
            if (error) *error = ModelProviderError(5, L(@"Choose an installed Ollama model.")); return NO;
        }
        if (model.length) [preferences setObject:model forKey:@"model"];
    }
    [preferences setObject:self.online ? @"online" : @"ollama" forKey:@"translationProvider"];
    _apiKey.stringValue = @"";
    return YES;
}
- (void)cancelPending {
    ++_generation;
    [_request cancel];
    _apiKey.stringValue = @"";
}
@end
