#import <Cocoa/Cocoa.h>
#import "Localization.h"

BOOL StartRime(BOOL deploy, NSError **error);
void StopRime(void);
enum { DefaultCandidateColumns = 5, MinimumCandidateColumns = 3, MaximumCandidateColumns = 9 };
NSInteger ReadCandidateColumns(void);
BOOL ReadLearningEnabled(void);
NSArray<NSString *> *InputLanguages(void);
NSString *ReadFirstInputLanguage(void);
NSString *ReadSecondInputLanguage(void);
NSString *PairTranslationTarget(NSString *text, NSString *fallbackSource);
BOOL InputLanguageUsesPinyin(NSString *language);
BOOL InputLanguageUsesCandidates(NSString *language);
BOOL InputLanguageUsesCapsLock(NSString *language);
NSString *InputLanguageForModifiers(NSEventModifierFlags flags);
NSArray<NSMenuItem *> *CreateInputLanguageMenuItems(NSString *language);

@interface CandidatePage : NSObject
@property(nonatomic, copy, readonly) NSArray<NSString *> *candidates;
@property(nonatomic, readonly) NSInteger highlighted;
@property(nonatomic, readonly) NSInteger index;
@property(nonatomic, readonly) BOOL hasPreviousPage;
@property(nonatomic, readonly) BOOL hasNextPage;
- (instancetype)initWithCandidates:(NSArray<NSString *> *)candidates highlighted:(NSInteger)highlighted index:(NSInteger)index hasNextPage:(BOOL)hasNextPage;
@end

@interface CandidateListView : NSStackView
@property(nonatomic, copy) void (^choose)(NSUInteger);
@property(nonatomic, copy) void (^changePage)(BOOL);
@property(nonatomic, copy) void (^setExpanded)(BOOL);
@property(nonatomic) CGFloat maximumWidth;
@property(nonatomic) CGFloat maximumHeight;
@property(nonatomic, readonly) CGFloat contentWidth;
- (void)updateWithPage:(CandidatePage *)page expanded:(BOOL)expanded columns:(NSInteger)columns;
@end

@interface PinyinEngine : NSObject
@property(nonatomic, copy, readonly) NSString *language;
- (instancetype)initWithLanguage:(NSString *)language;
@property(nonatomic) BOOL learningEnabled;
@property(nonatomic, readonly) NSString *preedit;
@property(nonatomic, readonly) NSString *rawInput;
@property(nonatomic, readonly) NSString *literalInput;
@property(nonatomic, readonly) NSUInteger literalCaret;
@property(nonatomic) NSUInteger caret;
@property(nonatomic, readonly) NSUInteger preeditCaret;
@property(nonatomic, readonly) NSArray<NSString *> *candidates;
@property(nonatomic, readonly) NSInteger highlighted;
@property(nonatomic, readonly) CandidatePage *candidatePage;
- (BOOL)processKey:(int)key;
- (BOOL)choose:(NSUInteger)index;
- (BOOL)moveHighlight:(NSInteger)offset;
- (BOOL)changePage:(BOOL)backward;
- (NSString *)takeCommit;
- (void)clear;
- (NSDictionary *)editingState;
- (BOOL)restoreEditingState:(NSDictionary *)state;
@end

typedef void (^TranslationCompletion)(NSString *, NSError *);
typedef void (^TranslationService)(NSString *, TranslationCompletion);
NSString *TranslationTargetForText(NSString *text, NSString *preference);
NSArray<NSString *> *TranslationLanguages(void);
NSString *TranslationLanguageName(NSString *code);
NSString *TranslationLanguageBadge(NSString *code);
NSString *ReadTranslationSourceLanguage(void);
NSString *ReadTranslationTargetLanguage(void);
NSString *DetectInputLanguage(NSString *text);
NSString *ReadLastInputLanguage(void);
NSString *DefaultTranslationPrompt(void);
NSString *ReadTranslationPrompt(void);
NSURLRequest *MakeTranslationRequest(NSString *text, NSString *target);
NSURLRequest *MakeTranslationRequestForLanguages(NSString *text, NSString *source, NSString *target);
NSString *DecodeTranslation(NSData *data, NSInteger status);
NSString *TranslationWithSourceLayout(NSString *translation, NSString *source);
NSURLSessionDataTask *TranslateText(NSString *text, NSString *target, TranslationCompletion completion);
NSURLSessionDataTask *TranslateTextWithLanguages(NSString *text, NSString *source, NSString *target, TranslationCompletion completion);

@interface Composition : NSObject
@property(nonatomic, readonly) PinyinEngine *engine;
@property(nonatomic, copy, readonly) NSString *chinese;
@property(nonatomic, copy, readonly) NSString *english;
@property(nonatomic, copy, readonly) NSString *translationSourceLanguage;
@property(nonatomic, copy, readonly) NSString *translationTargetLanguage;
@property(nonatomic, copy, readonly) NSString *hint;
@property(nonatomic, readonly) NSUInteger chineseCaret;
@property(nonatomic, readonly) NSString *markedText;
@property(nonatomic, readonly) NSString *pendingKeyboardText;
@property(nonatomic, readonly) NSUInteger markedCaret;
@property(nonatomic, readonly) NSRange markedSelection;
@property(nonatomic, readonly) BOOL ready;
@property(nonatomic, readonly) BOOL hasComposition;
@property(nonatomic, readonly) BOOL hasEditingSession;
// Compatibility accessors for English/Chinese fixtures; production follows modifiers.
@property(nonatomic) BOOL directEnglish;
@property(nonatomic, readonly) BOOL inputEnglish;
@property(nonatomic, copy) NSString *baseInputLanguage;
@property(nonatomic, copy, readonly) NSString *inputLanguage;
@property(nonatomic, readonly) NSString *inputModeDescription;
@property(nonatomic, readonly) BOOL candidatesExpanded;
@property(nonatomic) NSInteger candidateColumns;
@property(nonatomic, copy) void (^changed)(void);
@property(nonatomic, copy) void (^committed)(NSString *);
// Receives only a detected source-language code when an automatic-source draft commits.
@property(nonatomic, copy) void (^inputLanguageCommitted)(NSString *);
@property(nonatomic, copy) void (^cancelled)(void);
@property(nonatomic, copy) TranslationService service;
@property(nonatomic, copy) void (^copyText)(NSString *);
@property(nonatomic, copy) NSString *(^pasteText)(void);
// The sentence view owns visual-line navigation. A zero delta resets its preferred column.
@property(nonatomic, copy) NSUInteger (^moveSentenceCaret)(NSUInteger caret, NSInteger lineDelta);
- (BOOL)handleKey:(NSUInteger)code text:(NSString *)text modifiers:(NSEventModifierFlags)flags;
- (BOOL)handlePhysicalKey:(NSUInteger)code text:(NSString *)text modifiers:(NSEventModifierFlags)flags;
- (void)synchronizeModifiers:(NSEventModifierFlags)flags;
- (BOOL)handleModifiers:(NSEventModifierFlags)flags;
- (void)chooseCandidate:(NSUInteger)index;
- (void)changeCandidatePage:(BOOL)backward;
- (void)expandCandidates;
- (void)collapseCandidates;
- (void)commitEnglish;
- (void)commitChinese;
- (void)cancel;
- (void)retry;
@end

@interface SentenceView : NSView
@property(nonatomic, readonly) NSTextView *textView;
@property(nonatomic, readonly) BOOL showsCaret;
@property(nonatomic, readonly) NSRect caretRect;
@property(nonatomic, readonly) NSRange selectionRange;
- (void)updateWithComposition:(Composition *)composition;
- (NSUInteger)moveCaret:(NSUInteger)caret byLines:(NSInteger)delta;
@end

NSStackView *CreateCompositionHeader(NSTextField *inputModeLabel);
NSView *CreateLanguageBadge(NSString *title);
NSStackView *CreateLanguageRow(NSString *title, NSTextField *text);
void UpdateTranslationLanguageRow(NSStackView *row, NSString *language);

int RunSelfTests(BOOL live);
int RunTranslationTests(BOOL live);
int RunLearningTests(BOOL verifyPersistence);
int RunLanguagePairTests(void);
int RunTypingEngineTests(void);
int RunJapaneseTests(void);
void ShowSettings(void);
NSArray<NSString *> *DecodeOllamaModels(NSData *data, NSError **error);
void ShowCandidatePreview(void);
