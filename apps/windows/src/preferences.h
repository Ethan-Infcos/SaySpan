#pragma once
#include "platform.h"
namespace sayspan {
inline std::wstring Preference(const wchar_t* name,const wchar_t* fallback) {
    wchar_t buffer[1024]{}; DWORD size=sizeof(buffer);
    return RegGetValueW(HKEY_CURRENT_USER,L"Software\\SaySpan",name,RRF_RT_REG_SZ,nullptr,buffer,&size)==ERROR_SUCCESS ? buffer : fallback;
}
inline DWORD PreferenceNumber(const wchar_t* name,DWORD fallback) {
    DWORD value=0,size=sizeof(value);
    return RegGetValueW(HKEY_CURRENT_USER,L"Software\\SaySpan",name,RRF_RT_REG_DWORD,nullptr,&value,&size)==ERROR_SUCCESS ? value : fallback;
}
inline std::wstring InputLanguage(bool second) { return Preference(second?L"SecondLanguage":L"FirstLanguage",second?L"zh":L"en"); }
inline bool CandidateLanguage(const std::wstring& language) { return language==L"zh" || language==L"zh-Hant" || language==L"ja"; }
inline void CompositionActivity(bool active) {
    HKEY key=nullptr;
    if(RegCreateKeyExW(HKEY_CURRENT_USER,L"Software\\SaySpan\\Activity",0,nullptr,0,KEY_SET_VALUE,nullptr,&key,nullptr)!=ERROR_SUCCESS)return;
    auto name=std::to_wstring(GetCurrentProcessId())+L"."+std::to_wstring(GetCurrentThreadId());
    if(active) { ULONGLONG time=GetTickCount64(); RegSetValueExW(key,name.c_str(),0,REG_QWORD,reinterpret_cast<BYTE*>(&time),sizeof(time)); }
    else RegDeleteValueW(key,name.c_str());
    RegCloseKey(key);
}
}
