#import "Core.h"
#include <rime_api.h>

static RimeApi *api;
static NSString *sharedPath;
static NSString *userPath;
static NSString *prebuiltPath;

BOOL StartRime(BOOL deploy, NSError **error) {
    sharedPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"Rime"];
    userPath = [NSProcessInfo processInfo].environment[@"DUALIME_USER_DIR"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/DualLineIME"];
    prebuiltPath = [sharedPath stringByAppendingPathComponent:@"build"];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:userPath withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    api = rime_get_api();
    RIME_STRUCT(RimeTraits, traits);
    traits.shared_data_dir = sharedPath.UTF8String;
    traits.user_data_dir = userPath.UTF8String;
    traits.prebuilt_data_dir = prebuiltPath.UTF8String;
    traits.distribution_name = AppDisplayName().UTF8String;
    traits.distribution_code_name = "dual_line";
    traits.distribution_version = "0.1.0";
    traits.app_name = "rime.dual_line";
    traits.min_log_level = 2;
    traits.log_dir = "";
    api->setup(&traits);
    api->initialize(&traits);
    if (deploy) {
        api->deployer_initialize(&traits);
        BOOL ok = api->deploy_config_file("default.yaml", "config_version");
        ok = api->deploy_schema([sharedPath stringByAppendingPathComponent:@"dual_line.schema.yaml"].UTF8String) && ok;
        ok = api->deploy_schema([sharedPath stringByAppendingPathComponent:@"dual_line_static.schema.yaml"].UTF8String) && ok;
        ok = api->deploy_schema([sharedPath stringByAppendingPathComponent:@"dual_line_traditional.schema.yaml"].UTF8String) && ok;
        ok = api->deploy_schema([sharedPath stringByAppendingPathComponent:@"dual_line_traditional_static.schema.yaml"].UTF8String) && ok;
        ok = api->deploy_schema([sharedPath stringByAppendingPathComponent:@"vokira_japanese_kana.schema.yaml"].UTF8String) && ok;
        ok = api->deploy_schema([sharedPath stringByAppendingPathComponent:@"vokira_japanese.schema.yaml"].UTF8String) && ok;
        ok = api->deploy_schema([sharedPath stringByAppendingPathComponent:@"vokira_japanese_static.schema.yaml"].UTF8String) && ok;
        if (!ok && error) *error = [NSError errorWithDomain:@"DualLineIME" code:1 userInfo:@{NSLocalizedDescriptionKey:L(@"Could not deploy the pinyin dictionary")}];
        return ok;
    }
    return YES;
}

void StopRime(void) { if (api) api->finalize(); }

@implementation CandidatePage
- (instancetype)initWithCandidates:(NSArray<NSString *> *)candidates highlighted:(NSInteger)highlighted index:(NSInteger)index hasNextPage:(BOOL)hasNextPage {
    if ((self = [super init])) {
        _candidates = [candidates copy];
        _highlighted = candidates.count ? MAX(0, MIN(highlighted, (NSInteger)candidates.count - 1)) : NSNotFound;
        _index = index;
        _hasNextPage = hasNextPage && candidates.count > 0;
    }
    return self;
}
- (BOOL)hasPreviousPage { return _candidates.count && _index > 0; }
@end

@implementation PinyinEngine {
    RimeSessionId _session;
    NSMutableArray *_editingActions;
    BOOL _replaying;
}
- (instancetype)init { return [self initWithLanguage:@"zh"]; }
- (instancetype)initWithLanguage:(NSString *)language {
    if ((self = [super init])) {
        _language = InputLanguageUsesCandidates(language) ? language.copy : @"zh";
        _session = api->create_session();
        _editingActions = [NSMutableArray array];
        _learningEnabled = ReadLearningEnabled();
        if (!_session || !api->select_schema(_session, [self schemaForLearning:_learningEnabled].UTF8String)) return nil;
    }
    return self;
}
- (void)dealloc { if (_session) api->destroy_session(_session); }
- (NSString *)schemaForLearning:(BOOL)enabled {
    if ([_language isEqual:@"ja"]) return enabled ? @"vokira_japanese" : @"vokira_japanese_static";
    if ([_language isEqual:@"zh-Hant"]) return enabled ? @"dual_line_traditional" : @"dual_line_traditional_static";
    return enabled ? @"dual_line" : @"dual_line_static";
}
- (void)setLearningEnabled:(BOOL)enabled {
    if (_learningEnabled == enabled) return;
    // Switching schemas changes both lookup and learning, without deleting data.
    if (api->select_schema(_session, [self schemaForLearning:enabled].UTF8String)) {
        _learningEnabled = enabled;
        [_editingActions removeAllObjects];
    }
}
- (void)recordAction:(NSArray *)action { if (!_replaying) [_editingActions addObject:action]; }
- (BOOL)processKey:(int)key {
    BOOL accepted = api->process_key(_session, key, 0);
    [self recordAction:@[@"key", @(key)]];
    return accepted;
}
- (BOOL)choose:(NSUInteger)index {
    CandidatePage *page = self.candidatePage;
    if (index >= page.candidates.count) return NO;
    BOOL accepted = api->select_candidate_on_current_page(_session, index);
    if (accepted) [self recordAction:@[@"choose", @(index), page.candidates[index]]];
    return accepted;
}
- (BOOL)moveHighlight:(NSInteger)offset {
    CandidatePage *page = self.candidatePage;
    if (!page.candidates.count) return NO;
    NSInteger next = page.highlighted + offset;
    if (next < 0 || next >= (NSInteger)page.candidates.count) return NO;
    if (RIME_API_AVAILABLE(api, highlight_candidate_on_current_page)) {
        if (!api->highlight_candidate_on_current_page(_session, next)) return NO;
    } else for (NSInteger i = 0; i < labs(offset); i++)
        if (!api->process_key(_session, offset < 0 ? 0xff52 : 0xff54, 0)) return NO;
    [self recordAction:@[@"highlight", @(offset)]];
    return YES;
}
- (BOOL)changePage:(BOOL)backward {
    CandidatePage *page = self.candidatePage;
    if (backward ? !page.hasPreviousPage : !page.hasNextPage) return NO;
    BOOL changed = RIME_API_AVAILABLE(api, change_page)
        ? api->change_page(_session, backward)
        : api->process_key(_session, backward ? 0xff55 : 0xff56, 0);
    if (changed && RIME_API_AVAILABLE(api, highlight_candidate_on_current_page))
        api->highlight_candidate_on_current_page(_session, 0);
    if (changed) [self recordAction:@[@"page", @(backward)]];
    return changed;
}
- (void)clear { api->clear_composition(_session); [_editingActions removeAllObjects]; }
- (NSString *)rawInput {
    const char *input = api->get_input(_session);
    return input ? @(input) : @"";
}
- (NSString *)literalInput {
    NSString *text = self.rawInput;
    RIME_STRUCT(RimeContext, context);
    if (api->get_context(_session, &context)) {
        // In this schema the preedit contains selected Chinese followed by the
        // remaining spelling, with apostrophes as its only display separators.
        // sel_start > 0 identifies a prefix already chosen by the user.
        if (context.composition.sel_start > 0 && context.composition.preedit)
            text = @(context.composition.preedit);
        api->free_context(&context);
    }
    return [text stringByReplacingOccurrencesOfString:@"'" withString:@""];
}
- (NSUInteger)caret { return api->get_caret_pos(_session); }
- (NSUInteger)literalCaret {
    NSString *text = self.rawInput;
    NSUInteger caret = self.caret;
    RIME_STRUCT(RimeContext, context);
    if (api->get_context(_session, &context)) {
        if (context.composition.sel_start > 0 && context.composition.preedit) {
            text = @(context.composition.preedit);
            caret = self.preeditCaret;
        }
        api->free_context(&context);
    }
    return [[[text substringToIndex:MIN(caret, text.length)] stringByReplacingOccurrencesOfString:@"'" withString:@""] length];
}
- (void)setCaret:(NSUInteger)caret {
    api->set_caret_pos(_session, MIN(caret, self.rawInput.length));
    [self recordAction:@[@"caret", @(self.caret)]];
}
- (NSUInteger)preeditCaret {
    RIME_STRUCT(RimeContext, context);
    if (!api->get_context(_session, &context)) return 0;
    // Rime offsets are UTF-8 bytes; AppKit selection ranges use UTF-16 units.
    const char *text = context.composition.preedit;
    NSUInteger bytes = text ? MIN((NSUInteger)MAX(0, context.composition.cursor_pos), strlen(text)) : 0;
    NSString *prefix = text ? [[NSString alloc] initWithBytes:text length:bytes encoding:NSUTF8StringEncoding] : @"";
    NSUInteger position = prefix.length;
    api->free_context(&context);
    return position;
}
- (NSString *)takeCommit {
    RIME_STRUCT(RimeCommit, commit);
    if (!api->get_commit(_session, &commit)) return @"";
    NSString *text = commit.text ? @(commit.text) : @"";
    api->free_commit(&commit);
    // History replays only unfinished conversions, never completed learning events.
    if (text.length) [_editingActions removeAllObjects];
    return text;
}
- (NSDictionary *)editingState {
    return @{@"actions":[_editingActions copy], @"raw":self.rawInput, @"literal":self.literalInput, @"caret":@(self.caret), @"language":_language};
}
- (BOOL)restoreEditingState:(NSDictionary *)state {
    if (state[@"language"] && ![state[@"language"] isEqual:_language]) return NO;
    [self clear];
    _replaying = YES;
    BOOL valid = YES;
    for (NSArray *action in state[@"actions"]) {
        NSString *kind = action[0];
        if ([kind isEqual:@"key"]) [self processKey:[action[1] intValue]];
        else if ([kind isEqual:@"caret"]) self.caret = [action[1] unsignedIntegerValue];
        else if ([kind isEqual:@"page"]) [self changePage:[action[1] boolValue]];
        else if ([kind isEqual:@"highlight"]) [self moveHighlight:[action[1] integerValue]];
        else if ([kind isEqual:@"choose"]) {
            NSUInteger index = [action[1] unsignedIntegerValue];
            NSArray *candidates = self.candidates;
            if (index < candidates.count && [candidates[index] isEqual:action[2]]) valid = [self choose:index];
            else {
                // Personal ranking may have changed since the snapshot. Match the word.
                RimeCandidateListIterator iterator = {0};
                NSInteger found = -1;
                if (api->candidate_list_begin(_session, &iterator)) {
                    while (api->candidate_list_next(&iterator) && iterator.index < 4096) {
                        if (iterator.candidate.text && [@(iterator.candidate.text) isEqual:action[2]]) { found = iterator.index; break; }
                    }
                    api->candidate_list_end(&iterator);
                }
                valid = found >= 0 && api->select_candidate(_session, found);
            }
            if (!valid) break;
        }
    }
    _replaying = NO;
    valid = valid && [self.rawInput isEqual:state[@"raw"]] && [self.literalInput isEqual:state[@"literal"]] && self.caret == [state[@"caret"] unsignedIntegerValue];
    if (valid) [_editingActions setArray:state[@"actions"]];
    else [self clear];
    return valid;
}
- (NSString *)preedit {
    RIME_STRUCT(RimeContext, context);
    if (!api->get_context(_session, &context)) return @"";
    NSString *text = context.composition.preedit ? @(context.composition.preedit) : @"";
    api->free_context(&context);
    return text;
}
- (CandidatePage *)candidatePage {
    RIME_STRUCT(RimeContext, context);
    if (!api->get_context(_session, &context))
        return [[CandidatePage alloc] initWithCandidates:@[] highlighted:NSNotFound index:0 hasNextPage:NO];
    NSMutableArray *result = [NSMutableArray array];
    for (int i = 0; i < context.menu.num_candidates; i++) {
        [result addObject:context.menu.candidates[i].text ? @(context.menu.candidates[i].text) : @""];
    }
    CandidatePage *page = [[CandidatePage alloc] initWithCandidates:result highlighted:context.menu.highlighted_candidate_index index:context.menu.page_no hasNextPage:!context.menu.is_last_page];
    api->free_context(&context);
    return page;
}
- (NSArray<NSString *> *)candidates { return self.candidatePage.candidates; }
- (NSInteger)highlighted { return self.candidatePage.highlighted; }
@end
