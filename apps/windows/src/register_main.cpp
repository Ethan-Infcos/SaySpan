#include "platform.h"
#include <iostream>
int wmain(int argc,wchar_t** argv) {
    using namespace sayspan;
    if(argc!=2) { std::wcerr<<L"Usage: SaySpanRegister --register | --unregister | --verify\n"; return 2; }
    HRESULT hr=CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED); if(FAILED(hr))return 3;
    std::wstring action=argv[1];
    if(action==L"--verify") {
        ComPtr<ITfInputProcessorProfileMgr> profiles; TF_INPUTPROCESSORPROFILE profile{};
        hr=CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&profiles));
        if(SUCCEEDED(hr)) {
            hr=profiles->GetProfile(TF_PROFILETYPE_INPUTPROCESSOR,ProfileLanguage,ServiceId,ProfileId,nullptr,&profile);
            std::wcout<<L"GetProfile: 0x"<<std::hex<<static_cast<unsigned long>(hr)<<L"\n";
        }
        if(SUCCEEDED(hr)) {
            ComPtr<ITfTextInputProcessorEx> service;
            hr=CoCreateInstance(ServiceId,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&service));
            std::wcout<<L"CreateService: 0x"<<std::hex<<static_cast<unsigned long>(hr)<<L"\n";
        }
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
