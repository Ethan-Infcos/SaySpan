#include "rime_engine.h"
#include "preferences.h"
#include <rime_api.h>
#include <shlobj.h>
#include <userenv.h>
#include <sddl.h>
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
bool ChineseUI() { auto language=Preference(L"InterfaceLanguage",L"auto"); return language==L"zh" || (language==L"auto" && PRIMARYLANGID(GetUserDefaultUILanguage())==LANG_CHINESE); }
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
    traits.distribution_code_name="sayspan_windows"; traits.distribution_version="0.2.1";
    traits.app_name="rime.sayspan"; traits.min_log_level=4; traits.log_dir="";
    api->setup(&traits); api->initialize(&traits);
    if (deploy) {
        api->deployer_initialize(&traits);
        if(!api->deploy_config_file("default.yaml","config_version"))return false;
        for(const wchar_t* schema : {L"sayspan.schema.yaml",L"sayspan_traditional.schema.yaml",L"vokira_japanese_kana.schema.yaml",L"vokira_japanese_static.schema.yaml"})
            if(!api->deploy_schema(utf8((data/schema).wstring()).c_str()))return false;
        return true;
    }
    return true;
}
RimeEngine::RimeEngine(const std::wstring& value):language(value) {
    std::lock_guard lock(mutex);
    if (!api) {
        PWSTR local=nullptr;
        HRESULT location=E_FAIL;
        if(InAppContainer()) {
            HANDLE token=nullptr;
            if(OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token)) {
                DWORD length=0;GetTokenInformation(token,TokenAppContainerSid,nullptr,0,&length);
                std::vector<BYTE> buffer(length);
                if(GetTokenInformation(token,TokenAppContainerSid,buffer.data(),length,&length)) {
                    LPWSTR sid=nullptr;
                    if(ConvertSidToStringSidW(reinterpret_cast<TOKEN_APPCONTAINER_INFORMATION*>(buffer.data())->TokenAppContainer,&sid)) {
                        location=GetAppContainerFolderPath(sid,&local);LocalFree(sid);
                    }
                }
                CloseHandle(token);
            }
        } else location=SHGetKnownFolderPath(FOLDERID_LocalAppData,0,nullptr,&local);
        if(FAILED(location))throw std::runtime_error("No application data directory");
        std::filesystem::path user=std::filesystem::path(local)/L"SaySpan"/L"Runtime"/std::to_wstring(GetCurrentProcessId());
        CoTaskMemFree(local);
        if (!InitializeRime(ModuleFolder()/L"data",user,false)) throw std::runtime_error("Rime initialization failed");
    }
    session=api->create_session();
    if (!session || !api->select_schema(session,language==L"ja"?"vokira_japanese_static":language==L"zh-Hant"?"sayspan_traditional":"sayspan")) {
        if (session) api->destroy_session(session);
        session=0; throw std::runtime_error("Pinyin schema is unavailable");
    }
}
RimeEngine::~RimeEngine() { std::lock_guard lock(mutex); if(session) api->destroy_session(session); }
void RimeEngine::refresh() const {
    if(!dirty)return; dirty=false;pool.clear();
    RimeCandidateListIterator iterator{};
    if(api->candidate_list_begin(session,&iterator)) {
        while(pool.size()<200 && api->candidate_list_next(&iterator)) pool.push_back({static_cast<size_t>(iterator.index),fromUtf8(iterator.candidate.text)});
        api->candidate_list_end(&iterator);
    }
    if(!PreferenceNumber(L"Learning",1))return;
    auto input=fromUtf8(api->get_input(session));
    if(input.empty() || input.size()>128)return;
    auto path=L"Software\\SaySpan\\Learning\\"+language+L"\\"+wide(input);
    HKEY key=nullptr; if(RegOpenKeyExW(HKEY_CURRENT_USER,path.c_str(),0,KEY_READ,&key)!=ERROR_SUCCESS)return;
    std::vector<DWORD> scores(pool.size());
    for(size_t i=0;i<pool.size();++i) {DWORD size=sizeof(DWORD);RegGetValueW(key,nullptr,wide(pool[i].second).c_str(),RRF_RT_REG_DWORD,nullptr,&scores[i],&size);}
    std::vector<size_t> order(pool.size()); for(size_t i=0;i<order.size();++i)order[i]=i;
    std::stable_sort(order.begin(),order.end(),[&](size_t a,size_t b){return scores[a]>scores[b];});
    auto original=pool;for(size_t i=0;i<order.size();++i)pool[i]=original[order[i]];
    RegCloseKey(key);
}
CandidateState RimeEngine::state() const {
    std::lock_guard lock(mutex);refresh();
    CandidateState result;RIME_STRUCT(RimeContext,context);
    if(api->get_context(session,&context)) {result.spelling=fromUtf8(context.composition.preedit);api->free_context(&context);}
    result.highlighted=highlighted;result.previous=pageStart>0;result.next=pageStart+pageSize<pool.size();
    for(size_t i=pageStart;i<std::min(pool.size(),pageStart+pageSize);++i)result.candidates.push_back(pool[i].second);
    return result;
}
void RimeEngine::type(char letter) {std::lock_guard lock(mutex);api->process_key(session,letter,0);changed();}
void RimeEngine::backspace() {std::lock_guard lock(mutex);api->process_key(session,0xff08,0);changed();}
void RimeEngine::remember(const std::u16string& candidate) {
    if(!PreferenceNumber(L"Learning",1))return;
    auto input=fromUtf8(api->get_input(session));if(input.empty() || input.size()>128)return;
    auto path=L"Software\\SaySpan\\Learning\\"+language+L"\\"+wide(input);
    HKEY key=nullptr;if(RegCreateKeyExW(HKEY_CURRENT_USER,path.c_str(),0,nullptr,0,KEY_READ|KEY_WRITE,nullptr,&key,nullptr)!=ERROR_SUCCESS)return;
    DWORD score=0,size=sizeof(score);auto name=wide(candidate);
    RegGetValueW(key,nullptr,name.c_str(),RRF_RT_REG_DWORD,nullptr,&score,&size);score=std::min<DWORD>(score+1,1000000);
    RegSetValueExW(key,name.c_str(),0,REG_DWORD,reinterpret_cast<BYTE*>(&score),sizeof(score));RegCloseKey(key);
}
void RimeEngine::choose(size_t index) {
    std::lock_guard lock(mutex);refresh();
    if(index<pageSize && pageStart+index<pool.size()) {auto candidate=pool[pageStart+index];remember(candidate.second);api->select_candidate(session,candidate.first);changed();}
}
void RimeEngine::move(int delta) {
    std::lock_guard lock(mutex);refresh(); if(pool.empty())return;
    auto position=std::clamp(static_cast<long long>(pageStart+highlighted)+delta,0LL,static_cast<long long>(pool.size()-1));
    pageStart=static_cast<size_t>(position)/pageSize*pageSize;highlighted=static_cast<size_t>(position)%pageSize;
}
void RimeEngine::page(bool backward) {
    std::lock_guard lock(mutex);refresh();
    if(backward)pageStart=pageStart>=pageSize?pageStart-pageSize:0;
    else if(pageStart+pageSize<pool.size())pageStart+=pageSize;
    highlighted=0;
}
void RimeEngine::expand(bool expanded,size_t columns) {std::lock_guard lock(mutex);auto position=pageStart+highlighted;pageSize=std::clamp<size_t>(columns,3,9)*(expanded?3:1);pageStart=position/pageSize*pageSize;highlighted=position%pageSize;}
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
void RimeEngine::confirm() { std::lock_guard lock(mutex); if(!state().candidates.empty())choose(highlighted); api->commit_composition(session);changed(); }
void RimeEngine::clear() { std::lock_guard lock(mutex); api->clear_composition(session);changed(); }
}
