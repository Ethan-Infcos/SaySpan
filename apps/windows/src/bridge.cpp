#include "bridge.h"
#include <sddl.h>
#include <shellapi.h>
namespace sayspan {
namespace {
std::wstring PipeName() {
    HANDLE token=nullptr; if(!OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token)) return {};
    DWORD size=0; GetTokenInformation(token,TokenUser,nullptr,0,&size); std::vector<BYTE> data(size);
    bool ok=GetTokenInformation(token,TokenUser,data.data(),size,&size)!=0; CloseHandle(token); if(!ok)return {};
    LPWSTR sid=nullptr; if(!ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(data.data())->User.Sid,&sid))return {};
    DWORD session=0; ProcessIdToSessionId(GetCurrentProcessId(),&session);
    auto result=L"\\\\.\\pipe\\SaySpan.v1."+std::wstring(sid)+L"."+std::to_wstring(session); LocalFree(sid); return result;
}
}
TranslationBridge::TranslationBridge():worker([this]{run();}) {}
TranslationBridge::~TranslationBridge() { stopping=true; ++serial; wake.notify_one(); if(worker.joinable())worker.join(); }
void TranslationBridge::launch(bool settings) {
    if(InAppContainer() || GetEnvironmentVariableW(L"SAYSPAN_TEST_NO_COMPANION",nullptr,0))return;
    if(!settings) {
        auto pipe=PipeName();
        if(pipe.size()>9) {auto name=L"Local\\"+pipe.substr(9);HANDLE running=OpenMutexW(SYNCHRONIZE,FALSE,name.c_str());if(running){CloseHandle(running);return;}}
    }
    auto path=ModuleFolder()/L"companion"/L"SaySpan.exe";
    ShellExecuteW(nullptr,L"open",path.c_str(),settings?L"--settings":L"--background",path.parent_path().c_str(),SW_SHOWNOACTIVATE);
}
void TranslationBridge::cancel() { ++serial; std::lock_guard lock(mutex); queued.reset(); reply.reset(); }
void TranslationBridge::submit(unsigned revision,std::wstring language,std::wstring text) {
    auto id=++serial;
    {std::lock_guard lock(mutex); queued=Request{id,revision,std::move(language),std::move(text)};reply.reset();} wake.notify_one();
}
std::optional<TranslationReply> TranslationBridge::take() { std::lock_guard lock(mutex); auto result=std::move(reply);reply.reset();return result; }
bool TranslationBridge::transfer(HANDLE pipe,void* data,DWORD size,bool write,unsigned request) {
    BYTE* position=static_cast<BYTE*>(data);
    while(size) {
        if(stopping || serial!=request)return false;
        OVERLAPPED operation{}; operation.hEvent=CreateEventW(nullptr,TRUE,FALSE,nullptr);if(!operation.hEvent)return false;
        DWORD done=0; BOOL ok=write?WriteFile(pipe,position,size,&done,&operation):ReadFile(pipe,position,size,&done,&operation);
        if(!ok && GetLastError()==ERROR_IO_PENDING) {
            ULONGLONG deadline=GetTickCount64()+95000;
            while(WaitForSingleObject(operation.hEvent,50)==WAIT_TIMEOUT && !stopping && serial==request && GetTickCount64()<deadline) {}
            if(stopping || serial!=request || GetTickCount64()>=deadline)CancelIoEx(pipe,&operation);
            ok=GetOverlappedResult(pipe,&operation,&done,TRUE);
        }
        CloseHandle(operation.hEvent); if(!ok || !done || done>size)return false;
        position+=done; size-=done;
    }
    return true;
}
bool TranslationBridge::frame(HANDLE pipe,std::wstring& value,bool write,unsigned request) {
    DWORD length=write?static_cast<DWORD>(value.size()*sizeof(wchar_t)):0;
    if(!transfer(pipe,&length,sizeof(length),write,request) || length>131072 || length%2)return false;
    if(!write)value.resize(length/2);
    return !length || transfer(pipe,value.data(),length,write,request);
}
void TranslationBridge::run() {
    for(;;) {
        Request request;
        {std::unique_lock lock(mutex);wake.wait(lock,[this]{return stopping || queued.has_value();});if(stopping)return;request=std::move(*queued);queued.reset();}
        TranslationReply result{request.revision,false,L"",L"Open Settings → Models to configure translation."};
        const bool restricted=InAppContainer();
        if(restricted)result.text=ChineseUI()?L"此应用限制句子翻译。按 Enter 输入原文。":L"Translation is unavailable in this restricted app. Press Enter to insert the source.";
        HANDLE pipe=INVALID_HANDLE_VALUE;
        auto name=PipeName();
        // Restricted hosts retain source input without bypassing container IPC rules.
        for(int attempt=0;!restricted && attempt<15 && !stopping && serial==request.serial;++attempt) {
            pipe=CreateFileW(name.c_str(),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_EXISTING,FILE_FLAG_OVERLAPPED|SECURITY_SQOS_PRESENT|SECURITY_IDENTIFICATION,nullptr);
            if(pipe!=INVALID_HANDLE_VALUE)break;
            if(attempt==0)launch();
            std::unique_lock lock(mutex);wake.wait_for(lock,std::chrono::milliseconds(100),[this,&request]{return stopping || serial!=request.serial;});
        }
        if(pipe!=INVALID_HANDLE_VALUE) {
            ULONG serverId=0;bool trusted=false;
            if(GetNamedPipeServerProcessId(pipe,&serverId)) {
                HANDLE process=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,serverId);
                if(process) {wchar_t path[32768]{};DWORD length=32768;
                    if(QueryFullProcessImageNameW(process,0,path,&length))trusted=_wcsicmp(path,(ModuleFolder()/L"companion"/L"SaySpan.exe").c_str())==0;
                    CloseHandle(process);
                }
            }
            if(!trusted) {CloseHandle(pipe);pipe=INVALID_HANDLE_VALUE;}
        }
        if(pipe!=INVALID_HANDLE_VALUE) {
            std::wstring operation=L"translate",status;
            if(frame(pipe,operation,true,request.serial) && frame(pipe,request.language,true,request.serial) && frame(pipe,request.text,true,request.serial) &&
               frame(pipe,status,false,request.serial) && frame(pipe,result.target,false,request.serial) && frame(pipe,result.text,false,request.serial)) result.success=status==L"ok";
            CloseHandle(pipe);
        }
        if(!stopping && serial==request.serial) {std::lock_guard lock(mutex); if(serial==request.serial)reply=std::move(result);}
    }
}
}
