#pragma once
#include "platform.h"
#include "branding.h"
namespace sayspan {
inline std::wstring ModeTitle() { return std::wstring(AppName)+(ChineseUI()?L" · 中文":L" · Chinese"); }
inline const wchar_t* EditorHint(bool pending) {
    if(!pending) return ChineseUI()?L"Enter 上屏 · Shift + 方向键选择":L"Enter: insert · Shift + arrows: select";
    return ChineseUI()?L"空格选词 · 方向键 / PgUp / PgDn · Enter 保留字母":L"Space: choose · Arrows / PgUp / PgDn · Enter: keep letters";
}
}
