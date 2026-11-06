#pragma once
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <msctf.h>
#include <wrl/client.h>
#include <string>
#include <filesystem>
#include <atomic>
#include "editor.h"
namespace sayspan {
using Microsoft::WRL::ComPtr;
inline const CLSID ServiceId = {0x8f56c42a,0x2ab9,0x4d51,{0xa8,0xdf,0x8d,0x23,0xe7,0xb2,0x10,0x61}};
inline const GUID ProfileId = {0x213c9793,0x44b2,0x441a,{0x8c,0x32,0xb9,0x71,0xad,0x1b,0x3e,0x40}};
inline constexpr LANGID ProfileLanguage = 0x0804;
extern HINSTANCE module;
extern std::atomic<long> objects;
std::filesystem::path ModuleFolder();
inline std::wstring wide(const std::u16string& s) { static_assert(sizeof(wchar_t)==2); return {s.begin(),s.end()}; }
inline std::u16string utf16(const std::wstring& s) { return {s.begin(),s.end()}; }
std::string utf8(const std::wstring& s);
std::u16string fromUtf8(const char* s);
bool ChineseUI();
inline bool InAppContainer() {
    HANDLE token=nullptr;DWORD restricted=0,size=sizeof(restricted);
    if(!OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token))return false;
    bool ok=GetTokenInformation(token,TokenIsAppContainer,&restricted,size,&size)!=0;
    CloseHandle(token);return ok && restricted!=0;
}
}
