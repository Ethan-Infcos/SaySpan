#include "rime_engine.h"
#include <rime_api.h>
#include <shlobj.h>
#include <mutex>
#include <stdexcept>
#include <cstring>
namespace sayspan {
namespace {
std::recursive_mutex mutex;
RimeApi* api = nullptr;
// Rime stays loaded for the host process lifetime. Never finalize under the loader lock.
HMODULE rimeModule = nullptr;
std::string sharedPath, userPath, buildPath;
}
std::filesystem::path ModuleFolder() {
    wchar_t path[32768]{};
    DWORD length=GetModuleFileNameW(module,path,32768);
    if (!length || length==32768) throw std::runtime_error("Cannot locate SaySpan module");
    return std::filesystem::path(path).parent_path();
}
std::string utf8(const std::wstring& s) {
    if (s.empty()) return {};
    int size=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,s.data(),static_cast<int>(s.size()),nullptr,0,nullptr,nullptr);
    if (!size) throw std::runtime_error("Invalid UTF-16");
    std::string result(size,0);
    WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,s.data(),static_cast<int>(s.size()),result.data(),size,nullptr,nullptr);
    return result;
}
std::u16string fromUtf8(const char* s) {
    if (!s || !*s) return {};
    int size=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s,-1,nullptr,0);
    if (!size) throw std::runtime_error("Invalid UTF-8");
    std::wstring result(size,0);
    MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s,-1,result.data(),size);
    result.pop_back(); return utf16(result);
}
bool ChineseUI() { return PRIMARYLANGID(GetUserDefaultUILanguage())==LANG_CHINESE; }
bool RimeInitialized() { return api!=nullptr; }
bool InitializeRime(const std::filesystem::path& data,const std::filesystem::path& user,bool deploy) {
    std::lock_guard lock(mutex);
    if (api) return !deploy;
    std::filesystem::create_directories(user);
    auto dll=ModuleFolder()/L"rime.dll";
    rimeModule=LoadLibraryExW(dll.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!rimeModule) return false;
    auto getApi=reinterpret_cast<RimeApi*(*)()>(GetProcAddress(rimeModule,"rime_get_api"));
    if (!getApi) return false;
    api=getApi();
    sharedPath=utf8(data.wstring()); userPath=utf8(user.wstring()); buildPath=utf8((data/L"build").wstring());
    RIME_STRUCT(RimeTraits,traits);
    traits.shared_data_dir=sharedPath.c_str(); traits.user_data_dir=userPath.c_str();
    traits.prebuilt_data_dir=buildPath.c_str(); traits.distribution_name="SaySpan";
    traits.distribution_code_name="sayspan_windows"; traits.distribution_version="0.1.0";
    traits.app_name="rime.sayspan"; traits.min_log_level=4; traits.log_dir="";
    api->setup(&traits); api->initialize(&traits);
    if (deploy) {
        api->deployer_initialize(&traits);
        return api->deploy_config_file("default.yaml","config_version") &&
               api->deploy_schema(utf8((data/L"sayspan.schema.yaml").wstring()).c_str());
    }
    return true;
}
RimeEngine::RimeEngine() {
    std::lock_guard lock(mutex);
    if (!api) {
        PWSTR local=nullptr;
        if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData,0,nullptr,&local))) throw std::runtime_error("No user data directory");
        std::filesystem::path user=std::filesystem::path(local)/L"SaySpan"/L"Runtime"/std::to_wstring(GetCurrentProcessId());
        CoTaskMemFree(local);
        if (!InitializeRime(ModuleFolder()/L"data",user,false)) throw std::runtime_error("Rime initialization failed");
    }
    session=api->create_session();
    if (!session || !api->select_schema(session,"sayspan")) {
        if (session) api->destroy_session(session);
        session=0; throw std::runtime_error("Pinyin schema is unavailable");
    }
}
RimeEngine::~RimeEngine() { std::lock_guard lock(mutex); if(session) api->destroy_session(session); }
CandidateState RimeEngine::state() const {
    std::lock_guard lock(mutex);
    CandidateState result;
    RIME_STRUCT(RimeContext,context);
    if (api->get_context(session,&context)) {
        result.spelling=fromUtf8(context.composition.preedit);
        result.highlighted=static_cast<size_t>(std::max(0,context.menu.highlighted_candidate_index));
        result.previous=context.menu.page_no>0; result.next=!context.menu.is_last_page;
        for (int i=0;i<context.menu.num_candidates;++i) result.candidates.push_back(fromUtf8(context.menu.candidates[i].text));
        api->free_context(&context);
    }
    return result;
}
void RimeEngine::type(char letter) { std::lock_guard lock(mutex); api->process_key(session,letter,0); }
void RimeEngine::backspace() { std::lock_guard lock(mutex); api->process_key(session,0xff08,0); }
void RimeEngine::choose(size_t index) {
    std::lock_guard lock(mutex);
    if(index<state().candidates.size()) api->select_candidate_on_current_page(session,index);
}
void RimeEngine::move(int delta) {
    std::lock_guard lock(mutex);
    api->process_key(session,delta<0?0xff52:0xff54,0);
}
void RimeEngine::page(bool backward) { std::lock_guard lock(mutex); api->change_page(session,backward); }
std::u16string RimeEngine::takeCommit() {
    std::lock_guard lock(mutex);
    RIME_STRUCT(RimeCommit,commit); std::u16string result;
    if(api->get_commit(session,&commit)) { result=fromUtf8(commit.text); api->free_commit(&commit); }
    return result;
}
std::u16string RimeEngine::literal() const {
    std::lock_guard lock(mutex);
    auto result=fromUtf8(api->get_input(session));
    RIME_STRUCT(RimeContext,context);
    if(api->get_context(session,&context)) {
        if(context.composition.sel_start>0) result=fromUtf8(context.composition.preedit);
        api->free_context(&context);
    }
    result.erase(std::remove(result.begin(),result.end(),u'\''),result.end()); return result;
}
void RimeEngine::confirm() { std::lock_guard lock(mutex); api->commit_composition(session); }
void RimeEngine::clear() { std::lock_guard lock(mutex); api->clear_composition(session); }
}
