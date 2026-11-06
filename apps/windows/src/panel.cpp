#include "panel.h"
#include "ui.h"
#include <windowsx.h>
#include <climits>
namespace sayspan {
Panel::~Panel() { tick={}; if(window) DestroyWindow(window); if(font) DeleteObject(font); }
bool Panel::ensureWindow() {
    if(window)return true;
    WNDCLASSEXW wc{sizeof(wc)};wc.hInstance=module;wc.lpfnWndProc=procedure;wc.lpszClassName=L"SaySpan.CandidatePanel.v2";wc.hCursor=LoadCursor(nullptr,IDC_ARROW);
    if(!RegisterClassExW(&wc) && GetLastError()!=ERROR_CLASS_ALREADY_EXISTS)return false;
    window=CreateWindowExW(WS_EX_TOPMOST|WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE,wc.lpszClassName,AppName,WS_POPUP|WS_BORDER,0,0,1,1,nullptr,nullptr,module,this);
    return window!=nullptr;
}
void Panel::watch(std::function<void()> callback) {tick=std::move(callback);if(ensureWindow())SetTimer(window,1,100,nullptr);}
void Panel::hide() {select={};if(window)ShowWindow(window,SW_HIDE);}
void Panel::refresh(const Editor& editor) {auto callback=select;show(editor,lastCaret,std::move(callback));}
void Panel::layout(HDC dc,int maxWidth) {
    width=std::min(px(680),maxWidth);
    positions.assign(sentence.size()+1,{});
    int x=px(14),y=0,line=px(26);
    for(size_t i=0;i<sentence.size();) {
        size_t count=(sentence[i]>=0xd800 && sentence[i]<=0xdbff && i+1<sentence.size())?2:1;
        SIZE size{};GetTextExtentPoint32W(dc,sentence.data()+i,static_cast<int>(count),&size);
        if(sentence[i]!=L'\n' && x+size.cx>width-px(14) && x>px(14)){x=px(14);y+=line;}
        positions[i]={x,y};if(count==2)positions[i+1]=positions[i];
        if(sentence[i]==L'\n'){x=px(14);y+=line;}else x+=size.cx;
        i+=count;positions[i]={x,y};
    }
    sourceHeight=std::min(y+line,px(156));sourceTop=px(38);
    sourceScroll=std::max(0,static_cast<int>(positions[std::min(caretPosition,sentence.size())].y)-sourceHeight+line);
    translationTop=sourceTop+sourceHeight+px(12);translationHeight=0;
    if(!translation.empty() || !status.empty()) {
        RECT measure{0,0,width-px(28),0};auto& text=translation.empty()?status:translation;
        DrawTextW(dc,text.c_str(),-1,&measure,DT_CALCRECT|DT_WORDBREAK|DT_NOPREFIX|DT_EXPANDTABS);
        translationHeight=std::clamp(static_cast<int>(measure.bottom)+px(24),px(48),px(180));
    }
    boxes.clear();y=translationTop+translationHeight;
    size_t count=std::max<size_t>(1,columns);
    std::vector<int> widths(count,px(45));
    for(size_t i=0;i<candidates.candidates.size();++i) {
        auto label=std::to_wstring(i%count+1)+L"  "+wide(candidates.candidates[i]);SIZE size{};
        GetTextExtentPoint32W(dc,label.c_str(),static_cast<int>(label.size()),&size);widths[i%count]=std::max(widths[i%count],static_cast<int>(size.cx)+px(22));
    }
    int available=width-px(28)-static_cast<int>(count-1)*px(6),total=0;for(auto w:widths)total+=w;
    if(total>available)for(auto& w:widths)w=std::max(px(30),MulDiv(w,available,total));
    for(size_t row=0;row<candidates.candidates.size();row+=count) {
        int h=px(32);x=px(14);
        for(size_t i=row;i<std::min(row+count,candidates.candidates.size());++i) {
            auto label=std::to_wstring(i%count+1)+L"  "+wide(candidates.candidates[i]);RECT m{0,0,widths[i%count]-px(18),0};DrawTextW(dc,label.c_str(),-1,&m,DT_CALCRECT|DT_WORDBREAK|DT_NOPREFIX);h=std::max(h,static_cast<int>(m.bottom)+px(10));
        }
        for(size_t i=row;i<std::min(row+count,candidates.candidates.size());++i) {int w=widths[i%count];boxes.push_back({x,y,x+w,y+h});x+=w+px(6);}y+=h+px(6);
    }
    height=y+px(34);
}
void Panel::show(const Editor& editor,RECT caret,std::function<void(size_t)> choose) {
    if(!editor.active()){hide();return;}
    sentence=wide(editor.marked());candidates=editor.candidates();translation=wide(editor.translation);status=wide(editor.translationStatus);language=editor.language;columns=editor.columns;
    caretPosition=editor.markedCaret();selectionStart=editor.pending()?caretPosition:editor.draft.start();selectionEnd=editor.pending()?caretPosition:editor.draft.end();
    lastCaret=caret;select=std::move(choose);if(!ensureWindow())return;
    MONITORINFO monitor{sizeof(monitor)};GetMonitorInfoW(MonitorFromRect(&caret,MONITOR_DEFAULTTONEAREST),&monitor);
    HWND owner=GetFocus();scale=owner?GetDpiForWindow(owner):96;if(!scale)scale=96;
    if(font)DeleteObject(font);font=CreateFontW(-px(16),0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Segoe UI");
    HDC dc=GetDC(window);auto old=SelectObject(dc,font);layout(dc,std::max(px(240),static_cast<int>(monitor.rcWork.right-monitor.rcWork.left)-px(16)));SelectObject(dc,old);ReleaseDC(window,dc);
    int x=std::clamp(static_cast<int>(caret.left),static_cast<int>(monitor.rcWork.left),std::max(static_cast<int>(monitor.rcWork.left),static_cast<int>(monitor.rcWork.right)-width));
    int y=caret.bottom+px(6);if(y+height>monitor.rcWork.bottom)y=caret.top-height-px(6);y=std::max(static_cast<int>(monitor.rcWork.top),y);
    SetWindowPos(window,HWND_TOPMOST,x,y,width,height,SWP_NOACTIVATE|SWP_SHOWWINDOW);InvalidateRect(window,nullptr,FALSE);
}
bool Panel::moveVertical(Draft& draft,int direction,bool extend) {
    if(positions.size()!=draft.text.size()+1 || positions.empty())return false;
    auto point=positions[std::min(draft.caret,positions.size()-1)];LONG target=point.y+direction*px(26);size_t best=draft.caret;LONG distance=LONG_MAX;
    for(size_t i=0;i<positions.size();++i) {
        if(i && i<draft.text.size() && draft.text[i]>=0xdc00 && draft.text[i]<=0xdfff)continue;
        if(positions[i].y==target && std::abs(positions[i].x-point.x)<distance){distance=std::abs(positions[i].x-point.x);best=i;}
    }
    if(distance==LONG_MAX)best=direction<0?0:draft.text.size();draft.caret=best;if(!extend)draft.anchor=best;return true;
}
void Panel::paint() {
    PAINTSTRUCT ps;HDC dc=BeginPaint(window,&ps);RECT client{};GetClientRect(window,&client);
    auto brush=CreateSolidBrush(RGB(248,249,252));FillRect(dc,&client,brush);DeleteObject(brush);auto previous=SelectObject(dc,font);SetBkMode(dc,TRANSPARENT);
    SetTextColor(dc,RGB(100,107,120));RECT title{px(14),px(8),width/2,px(31)};
    auto heading=std::wstring(AppName)+L" · "+language;DrawTextW(dc,heading.c_str(),-1,&title,DT_SINGLELINE|DT_NOPREFIX);
    RECT actions{width/2,px(8),width-px(14),px(31)};DrawTextW(dc,ChineseUI()?L"Enter 原文 · Tab 译文":L"Enter: source · Tab: translation",-1,&actions,DT_SINGLELINE|DT_RIGHT|DT_NOPREFIX);
    int saved=SaveDC(dc);IntersectClipRect(dc,px(14),sourceTop,width-px(14),sourceTop+sourceHeight);
    for(size_t i=0;i<sentence.size();) {
        size_t count=sentence[i]>=0xd800 && sentence[i]<=0xdbff && i+1<sentence.size()?2:1;auto point=positions[i];int y=sourceTop+point.y-sourceScroll;
        if(i>=selectionStart && i<selectionEnd) {SIZE size{};GetTextExtentPoint32W(dc,sentence.data()+i,static_cast<int>(count),&size);RECT rect{point.x,y,point.x+size.cx,y+px(26)};auto b=CreateSolidBrush(RGB(199,221,255));FillRect(dc,&rect,b);DeleteObject(b);}
        SetTextColor(dc,RGB(24,30,44));if(sentence[i]!=L'\n')TextOutW(dc,point.x,y,sentence.data()+i,static_cast<int>(count));i+=count;
    }
    if(selectionStart==selectionEnd && caretPosition<positions.size()) {
        auto point=positions[caretPosition];auto pen=CreatePen(PS_SOLID,px(1),RGB(35,90,210));auto old=SelectObject(dc,pen);MoveToEx(dc,point.x,sourceTop+point.y-sourceScroll,nullptr);LineTo(dc,point.x,sourceTop+point.y-sourceScroll+px(23));SelectObject(dc,old);DeleteObject(pen);
    }
    RestoreDC(dc,saved);
    if(translationHeight) {
        RECT tag{px(14),translationTop,width-px(14),translationTop+px(22)};SetTextColor(dc,RGB(100,107,120));DrawTextW(dc,ChineseUI()?L"译文":L"Translation",-1,&tag,DT_SINGLELINE);
        RECT body{px(14),translationTop+px(24),width-px(14),translationTop+translationHeight};SetTextColor(dc,translation.empty()?RGB(100,107,120):RGB(24,30,44));auto& text=translation.empty()?status:translation;DrawTextW(dc,text.c_str(),-1,&body,DT_WORDBREAK|DT_NOPREFIX|DT_EXPANDTABS);
    }
    for(size_t i=0;i<boxes.size();++i) {
        if(i==candidates.highlighted){auto b=CreateSolidBrush(RGB(215,230,255));FillRect(dc,&boxes[i],b);DeleteObject(b);}
        auto label=std::to_wstring(i%columns+1)+L"  "+wide(candidates.candidates[i]);RECT box=boxes[i];InflateRect(&box,-px(9),-px(4));SetTextColor(dc,RGB(24,30,44));DrawTextW(dc,label.c_str(),-1,&box,DT_WORDBREAK|DT_NOPREFIX);
    }
    RECT footer{px(14),height-px(28),width-px(12),height-px(5)};SetTextColor(dc,RGB(100,107,120));DrawTextW(dc,EditorHint(!candidates.spelling.empty()),-1,&footer,DT_SINGLELINE|DT_NOPREFIX);
    SelectObject(dc,previous);EndPaint(window,&ps);
}
LRESULT CALLBACK Panel::procedure(HWND window,UINT message,WPARAM wParam,LPARAM lParam) {
    auto self=reinterpret_cast<Panel*>(GetWindowLongPtrW(window,GWLP_USERDATA));if(message==WM_NCCREATE){self=static_cast<Panel*>(reinterpret_cast<CREATESTRUCTW*>(lParam)->lpCreateParams);SetWindowLongPtrW(window,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(self));}
    if(self) {
        if(message==WM_TIMER){if(self->tick)self->tick();return 0;}
        if(message==WM_MOUSEACTIVATE)return MA_NOACTIVATE;
        if(message==WM_PAINT){self->paint();return 0;}
        if(message==WM_ERASEBKGND)return 1;
        if(message==WM_LBUTTONUP){POINT point{GET_X_LPARAM(lParam),GET_Y_LPARAM(lParam)};for(size_t i=0;i<self->boxes.size();++i)if(PtInRect(&self->boxes[i],point)){auto callback=self->select;if(callback)callback(i);break;}return 0;}
    }
    return DefWindowProcW(window,message,wParam,lParam);
}
}
