#include "platform.h"
#include <iostream>
int wmain(int argc,wchar_t** argv) {
    using namespace sayspan;
    if(argc!=2) { std::wcerr<<L"Usage: SaySpanRegister --register | --unregister | --verify\n"; return 2; }
    HRESULT hr=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED); if(FAILED(hr))return 3;
    std::wstring action=argv[1];
    if(action==L"--verify") {
        ComPtr<ITfTextInputProcessorEx> service;
        HRESULT server=CoCreateInstance(ServiceId,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&service));
        std::wcout<<L"CreateService: 0x"<<std::hex<<static_cast<unsigned long>(server)<<L"\n";
        ComPtr<ITfInputProcessorProfileMgr> profiles;
        hr=CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&profiles));
        if(SUCCEEDED(hr)) {
            ComPtr<IEnumTfInputProcessorProfiles> list;
            hr=profiles->EnumProfiles(ProfileLanguage,&list);
            if(SUCCEEDED(hr)) {
                TF_INPUTPROCESSORPROFILE profile{}; ULONG count=0; bool found=false;
                while(list->Next(1,&profile,&count)==S_OK && count==1) {
                    if(profile.clsid==ServiceId && profile.guidProfile==ProfileId) { found=true; break; }
                }
                hr=found?S_OK:E_FAIL;
            }
            std::wcout<<L"ProfileCatalog: 0x"<<std::hex<<static_cast<unsigned long>(hr)<<L"\n";
        }
        if(FAILED(server))hr=server;
    } else if(action==L"--register" || action==L"--unregister") {
        wchar_t path[32768]{}; GetModuleFileNameW(nullptr,path,32768);
        auto dll=std::filesystem::path(path).parent_path()/L"SaySpanTip.dll";
        HMODULE library=LoadLibraryExW(dll.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
        if(!library) hr=HRESULT_FROM_WIN32(GetLastError());
        else {
            auto function=reinterpret_cast<HRESULT(WINAPI*)()>(GetProcAddress(library,action==L"--register"?"DllRegisterServer":"DllUnregisterServer"));
            hr=function?function():E_NOINTERFACE;
            FreeLibrary(library);
        }
    } else hr=E_INVALIDARG;
    CoUninitialize();
    if(FAILED(hr)) { std::wcerr<<L"SaySpan registration failed: 0x"<<std::hex<<static_cast<unsigned long>(hr)<<L"\n";return 1; }
    std::wcout<<L"SaySpan: "<<action<<L" succeeded\n";return 0;
}
