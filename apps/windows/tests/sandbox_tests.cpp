// Isolated CI only: exercise the shipped dictionaries with an actual AppContainer token.
#include "platform.h"
#include <userenv.h>
#include <shlobj.h>
#include <iostream>
#include <stdexcept>
using namespace sayspan;
int wmain(int argc,wchar_t** argv) {
    if(argc!=2 || !GetEnvironmentVariableW(L"CI",nullptr,0))return 2;
    auto name=L"SaySpan.CI."+std::to_wstring(GetCurrentProcessId());
    PSID sid=nullptr;std::filesystem::path destination;
    LPPROC_THREAD_ATTRIBUTE_LIST attributes=nullptr;
    std::vector<BYTE> storage;bool initialized=false;
    HANDLE process=nullptr,thread=nullptr;int result=1;
    try {
        HRESULT hr=CreateAppContainerProfile(name.c_str(),L"SaySpan test",L"Isolated dictionary test",nullptr,0,&sid);
        if(FAILED(hr))throw std::runtime_error("Cannot create test AppContainer");
        PWSTR programs=nullptr;if(FAILED(SHGetKnownFolderPath(FOLDERID_ProgramFiles,0,nullptr,&programs)))throw std::runtime_error("No Program Files directory");
        destination=std::filesystem::path(programs)/name;CoTaskMemFree(programs);
        std::filesystem::create_directories(destination);
        auto source=std::filesystem::path(argv[1]);
        for(const auto* file:{L"runtime_tests.exe",L"rime.dll"})std::filesystem::copy_file(source/file,destination/file);
        std::filesystem::copy(source/L"data",destination/L"data",std::filesystem::copy_options::recursive);
        SIZE_T size=0;InitializeProcThreadAttributeList(nullptr,1,0,&size);
        storage.resize(size);attributes=reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage.data());
        if(!InitializeProcThreadAttributeList(attributes,1,0,&size))throw std::runtime_error("Cannot initialize process attributes");
        initialized=true;
        SECURITY_CAPABILITIES capabilities{};capabilities.AppContainerSid=sid;
        if(!UpdateProcThreadAttribute(attributes,0,PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES,&capabilities,sizeof(capabilities),nullptr,nullptr))throw std::runtime_error("Cannot configure test token");
        STARTUPINFOEXW startup{};startup.StartupInfo.cb=sizeof(startup);startup.lpAttributeList=attributes;
        PROCESS_INFORMATION info{};auto executable=(destination/L"runtime_tests.exe").wstring();auto command=L"\""+executable+L"\" --sandbox";
        BOOL created=CreateProcessW(executable.c_str(),command.data(),nullptr,nullptr,FALSE,EXTENDED_STARTUPINFO_PRESENT|CREATE_NO_WINDOW,nullptr,destination.c_str(),&startup.StartupInfo,&info);
        DWORD launchError=created?ERROR_SUCCESS:GetLastError();
        DeleteProcThreadAttributeList(attributes);initialized=false;attributes=nullptr;
        if(!created){std::cerr<<"Sandbox launch error "<<launchError<<'\n';throw std::runtime_error("Cannot launch test container");}
        process=info.hProcess;thread=info.hThread;
        if(WaitForSingleObject(process,30000)!=WAIT_OBJECT_0){TerminateProcess(process,1);throw std::runtime_error("Sandbox test timed out");}
        DWORD code=1;GetExitCodeProcess(process,&code);
        if(code){std::cerr<<"Sandbox exit code "<<code<<'\n';throw std::runtime_error("AppContainer dictionary/input test failed");}
        std::cout<<"AppContainer Chinese/Japanese candidate checks passed\n";result=0;
    }catch(const std::exception& error){std::cerr<<error.what()<<'\n';}
    if(initialized)DeleteProcThreadAttributeList(attributes);
    if(thread)CloseHandle(thread);if(process)CloseHandle(process);
    if(sid){DeleteAppContainerProfile(name.c_str());FreeSid(sid);}
    if(!destination.empty()){std::error_code error;std::filesystem::remove_all(destination,error);}
    return result;
}
