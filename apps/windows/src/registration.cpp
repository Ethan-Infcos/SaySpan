#include "platform.h"
#include "branding.h"
#include <string>
namespace sayspan {
std::wstring RegistryKey() {
    wchar_t guid[40]{}; StringFromGUID2(ServiceId,guid,40);
    return std::wstring(L"Software\\Classes\\CLSID\\")+guid;
}
HRESULT RegisterService(bool install) {
    ComPtr<ITfInputProcessorProfileMgr> profiles;
    HRESULT hr=CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&profiles));
    if(FAILED(hr))return hr;
    ComPtr<ITfCategoryMgr> categories;
    hr=CoCreateInstance(CLSID_TF_CategoryMgr,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&categories));
    if(FAILED(hr))return hr;
    auto key=RegistryKey();
    if(!install) {
        HRESULT profile=profiles->UnregisterProfile(ServiceId,ProfileLanguage,ProfileId,0);
        for(const auto& category:{GUID_TFCAT_TIP_KEYBOARD,GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT})
            categories->UnregisterCategory(ServiceId,category,ServiceId);
        LONG status=RegDeleteTreeW(HKEY_LOCAL_MACHINE,key.c_str());
        if(status!=ERROR_SUCCESS && status!=ERROR_FILE_NOT_FOUND)return HRESULT_FROM_WIN32(status);
        return FAILED(profile) && profile!=E_INVALIDARG?profile:S_OK;
    }
    auto path=(ModuleFolder()/L"SaySpanTip.dll").wstring();
    HKEY handle=nullptr;
    LONG status=RegCreateKeyExW(HKEY_LOCAL_MACHINE,(key+L"\\InprocServer32").c_str(),0,nullptr,0,KEY_WRITE,nullptr,&handle,nullptr);
    if(status!=ERROR_SUCCESS)return HRESULT_FROM_WIN32(status);
    status=RegSetValueExW(handle,nullptr,0,REG_SZ,reinterpret_cast<const BYTE*>(path.c_str()),static_cast<DWORD>((path.size()+1)*sizeof(wchar_t)));
    const wchar_t threading[]=L"Apartment";
    if(status==ERROR_SUCCESS)status=RegSetValueExW(handle,L"ThreadingModel",0,REG_SZ,reinterpret_cast<const BYTE*>(threading),sizeof(threading));
    RegCloseKey(handle);
    if(status!=ERROR_SUCCESS)return HRESULT_FROM_WIN32(status);
    const wchar_t* name=ProfileName;
    hr=profiles->RegisterProfile(ServiceId,ProfileLanguage,ProfileId,name,static_cast<ULONG>(wcslen(name)),path.c_str(),static_cast<ULONG>(path.size()),0,nullptr,0,TRUE,0);
    for(const auto& category:{GUID_TFCAT_TIP_KEYBOARD,GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT})
        if(SUCCEEDED(hr))hr=categories->RegisterCategory(ServiceId,category,ServiceId);
    if(FAILED(hr)) {
        for(const auto& category:{GUID_TFCAT_TIP_KEYBOARD,GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT})categories->UnregisterCategory(ServiceId,category,ServiceId);
        profiles->UnregisterProfile(ServiceId,ProfileLanguage,ProfileId,0); RegDeleteTreeW(HKEY_LOCAL_MACHINE,key.c_str()); }
    return hr;
}
}
extern "C" HRESULT WINAPI DllRegisterServer(){try{return sayspan::RegisterService(true);}catch(...){return E_FAIL;}}
extern "C" HRESULT WINAPI DllUnregisterServer(){try{return sayspan::RegisterService(false);}catch(...){return E_FAIL;}}
