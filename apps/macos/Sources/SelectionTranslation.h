#import "Core.h"

enum { MaximumSelectionLength = 6000 };
BOOL ReadSelectionTranslationEnabled(void);
BOOL ReadSelectionTranslationAutomatic(void);
NSString *ReadSelectionTranslationTarget(void);
BOOL SelectionTranslationHasPermission(void);
void RequestSelectionTranslationPermission(void);
void StartSelectionTranslation(void);
void ShowSelectionTranslationPreview(void);
int RunSelectionTranslationTests(BOOL live);
void TraceSelectionEvent(NSString *event, NSDictionary *details);
BOOL SelectionApplicationUsesChromium(NSURL *bundleURL);
BOOL EnableSelectionWebAccessibility(BOOL chromium, NSNumber *(^read)(NSString *), BOOL (^enable)(NSString *));

// Main-thread coordination with InputMethodKit controllers, before writing marked text.
extern NSNotificationName const SelectionTranslationCompositionDidChangeNotification;
@protocol SelectionTranslationCompositionOwner <NSObject>
@property(nonatomic, readonly) BOOL selectionTranslationCompositionActive;
@end
BOOL SelectionTranslationCompositionActive(void);
void RefreshSelectionTranslationCompositionActivity(void);
void SetSelectionTranslationCompositionActive(id<SelectionTranslationCompositionOwner> owner, BOOL active);

NSRect SelectionRectFromAccessibility(CGRect rect, CGFloat primaryScreenTop);
NSRect SelectionPanelFrame(NSRect anchor, NSSize size, NSRect visibleFrame);

@interface TextSelection : NSObject <NSCopying>
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic) pid_t processID;
@property(nonatomic) NSRect anchor;
@property(nonatomic) BOOL tooLong;
- (BOOL)matches:(TextSelection *)other;
@end

typedef NS_ENUM(NSUInteger, SelectionTranslationStage) {
    SelectionTranslationHidden, SelectionTranslationBadge, SelectionTranslationResult, SelectionTranslationPending
};

@interface SelectionTranslation : NSObject
@property(nonatomic, readonly) TextSelection *selection;
@property(nonatomic, readonly) SelectionTranslationStage stage;
@property(nonatomic, readonly) NSString *result;
@property(nonatomic, readonly) NSString *status;
@property(nonatomic, readonly) NSString *target;
@property(nonatomic, readonly) NSString *sourceLanguage;
@property(nonatomic, readonly) BOOL loading;
@property(nonatomic) BOOL automaticallyTranslates;
@property(nonatomic) BOOL suspended;
@property(nonatomic, copy) void (^changed)(void);
@property(nonatomic, copy) NSURLSessionDataTask *(^service)(NSString *, NSString *, TranslationCompletion);
- (void)observeSelection:(TextSelection *)selection;
- (void)translateWithPreference:(NSString *)preference;
- (void)dismiss;
@end
