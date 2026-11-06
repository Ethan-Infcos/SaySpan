#include "panel.h"
#include <windowsx.h>
namespace sayspan {
Panel::~Panel() { if(window) DestroyWindow(window); if(font) DeleteObject(font); }
void Panel::hide() { if(window) ShowWindow(window,SW_HIDE); }
void Panel::layout(HDC dc,int maxWidth) {
    width=std::min(px(640),maxWidth);
    boxes.clear(); int x=px(14),y=px(78);
    for(size_t i=0;i<candidates.candidates.size();++i) {
        auto label=std::to_wstring(i+1)+L"  "+wide(candidates.candidates[i]);
        SIZE size{}; GetTextExtentPoint32W(dc,label.c_str(),static_cast<int>(label.size()),&size);
        int w=std::min(static_cast<int>(size.cx)+px(24),width-px(28));
        if(x+w>width-px(14)) { x=px(14); y+=px(36); }
        RECT measure{0,0,w-px(18),0};
        DrawTextW(dc,label.c_str(),-1,&measure,DT_CALCRECT|DT_WORDBREAK|DT_NOPREFIX);
        int h=std::max(px(30),static_cast<int>(measure.bottom)+px(10));
        boxes.push_back({x,y,x+w,y+h}); x+=w+px(6);
        if(h>px(30)) { y+=h+px(6); x=px(14); }
    }
    int bottom=px(72);
    for(const auto& box:boxes) bottom=std::max(bottom,static_cast<int>(box.bottom));
    height=bottom+px(36);
}
void Panel::show(const Editor& editor,RECT caret,std::function<void(size_t)> choose) {
    if(!editor.active()) { hide(); return; }
    sentence=wide(editor.marked()); candidates=editor.candidates();
    caretPosition=editor.markedCaret();
    selectionStart=editor.pending()?caretPosition:editor.draft.start();
    selectionEnd=editor.pending()?caretPosition:editor.draft.end();
    select=std::move(choose);
    if(!window) {
        WNDCLASSEXW wc{sizeof(wc)}; wc.hInstance=module; wc.lpfnWndProc=procedure;
        wc.lpszClassName=L"SaySpan.CandidatePanel.v1"; wc.hCursor=LoadCursor(nullptr,IDC_ARROW);
        if(!RegisterClassExW(&wc) && GetLastError()!=ERROR_CLASS_ALREADY_EXISTS) return;
        window=CreateWindowExW(WS_EX_TOPMOST|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,
            wc.lpszClassName,L"SaySpan",WS_POPUP|WS_BORDER,0,0,1,1,nullptr,nullptr,module,this);
        if(!window) return;
    }
    MONITORINFO monitor{sizeof(monitor)};
    GetMonitorInfoW(MonitorFromRect(&caret,MONITOR_DEFAULTTONEAREST),&monitor);
    HWND owner=GetFocus(); scale=owner?GetDpiForWindow(owner):96; if(!scale) scale=96;
    if(font) DeleteObject(font);
    font=CreateFontW(-px(16),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,
                     CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Segoe UI");
    HDC dc=GetDC(window); auto previous=SelectObject(dc,font);
    layout(dc,std::max(px(240),static_cast<int>(monitor.rcWork.right-monitor.rcWork.left)-px(16)));
    SelectObject(dc,previous); ReleaseDC(window,dc);
    int x=std::clamp(static_cast<int>(caret.left),static_cast<int>(monitor.rcWork.left),
                     std::max(static_cast<int>(monitor.rcWork.left),static_cast<int>(monitor.rcWork.right)-width));
    int y=caret.bottom+px(6);
    if(y+height>monitor.rcWork.bottom) y=caret.top-height-px(6);
    y=std::max(static_cast<int>(monitor.rcWork.top),y);
    SetWindowPos(window,HWND_TOPMOST,x,y,width,height,SWP_NOACTIVATE|SWP_SHOWWINDOW);
    InvalidateRect(window,nullptr,FALSE);
}
void Panel::paint() {
    PAINTSTRUCT ps; HDC dc=BeginPaint(window,&ps);
    RECT client{}; GetClientRect(window,&client);
    HBRUSH background=CreateSolidBrush(RGB(248,249,252)); FillRect(dc,&client,background); DeleteObject(background);
    auto previous=SelectObject(dc,font); SetBkMode(dc,TRANSPARENT);
    SetTextColor(dc,RGB(100,107,120));
    RECT title{px(14),px(8),width-px(14),px(31)};
    DrawTextW(dc,ChineseUI()?L"SaySpan · 中文":L"SaySpan · Chinese",-1,&title,DT_SINGLELINE|DT_NOPREFIX);
    int saved=SaveDC(dc); IntersectClipRect(dc,px(14),px(36),width-px(14),px(68));
    SIZE before{}; GetTextExtentPoint32W(dc,sentence.c_str(),static_cast<int>(std::min(caretPosition,sentence.size())),&before);
    int offset=std::max(0,static_cast<int>(before.cx)-(width-px(42)));
    if(selectionStart!=selectionEnd) {
        SIZE start{},end{};
        GetTextExtentPoint32W(dc,sentence.c_str(),static_cast<int>(selectionStart),&start);
        GetTextExtentPoint32W(dc,sentence.c_str(),static_cast<int>(selectionEnd),&end);
        RECT highlight{px(14)+start.cx-offset,px(37),px(14)+end.cx-offset,px(63)};
        auto brush=CreateSolidBrush(RGB(199,221,255)); FillRect(dc,&highlight,brush); DeleteObject(brush);
    }
    SetTextColor(dc,RGB(24,30,44)); TextOutW(dc,px(14)-offset,px(39),sentence.c_str(),static_cast<int>(sentence.size()));
    if(selectionStart==selectionEnd) {
        auto pen=CreatePen(PS_SOLID,px(1),RGB(35,90,210)); auto old=SelectObject(dc,pen);
        MoveToEx(dc,px(14)+before.cx-offset,px(38),nullptr); LineTo(dc,px(14)+before.cx-offset,px(62));
        SelectObject(dc,old); DeleteObject(pen);
    }
    RestoreDC(dc,saved);
    for(size_t i=0;i<boxes.size();++i) {
        if(i==candidates.highlighted) { auto brush=CreateSolidBrush(RGB(215,230,255)); FillRect(dc,&boxes[i],brush); DeleteObject(brush); }
        auto label=std::to_wstring(i+1)+L"  "+wide(candidates.candidates[i]);
        RECT box=boxes[i]; InflateRect(&box,-px(9),-px(4));
        SetTextColor(dc,RGB(24,30,44)); DrawTextW(dc,label.c_str(),-1,&box,DT_WORDBREAK|DT_NOPREFIX);
    }
    RECT footer{px(14),height-px(28),width-px(12),height-px(5)};
    SetTextColor(dc,RGB(100,107,120));
    const wchar_t* hint=candidates.spelling.empty() ?
        (ChineseUI()?L"Enter 上屏 · Shift + 方向键选择":L"Enter: insert · Shift + arrows: select") :
        (ChineseUI()?L"空格选词 · 方向键 / PgUp / PgDn · Enter 保留字母":L"Space: choose · Arrows / PgUp / PgDn · Enter: keep letters");
    DrawTextW(dc,hint,-1,&footer,DT_SINGLELINE|DT_NOPREFIX);
    SelectObject(dc,previous); EndPaint(window,&ps);
}
LRESULT CALLBACK Panel::procedure(HWND window,UINT message,WPARAM wParam,LPARAM lParam) {
    auto self=reinterpret_cast<Panel*>(GetWindowLongPtrW(window,GWLP_USERDATA));
    if(message==WM_NCCREATE) {
        self=static_cast<Panel*>(reinterpret_cast<CREATESTRUCTW*>(lParam)->lpCreateParams);
        SetWindowLongPtrW(window,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(self));
    }
    if(self) {
        if(message==WM_MOUSEACTIVATE) return MA_NOACTIVATE;
        if(message==WM_PAINT) { self->paint(); return 0; }
        if(message==WM_ERASEBKGND) return 1;
        if(message==WM_LBUTTONUP) {
            POINT point{GET_X_LPARAM(lParam),GET_Y_LPARAM(lParam)};
            for(size_t i=0;i<self->boxes.size();++i) if(PtInRect(&self->boxes[i],point)) {
                auto callback=self->select; if(callback) callback(i); break;
            }
            return 0;
        }
    }
    return DefWindowProcW(window,message,wParam,lParam);
}
}
