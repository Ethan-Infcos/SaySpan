#pragma once
#include "platform.h"
#include <functional>
namespace sayspan {
class Panel {
public:
    Panel() = default;
    ~Panel();
    void show(const Editor& editor, RECT caret, std::function<void(size_t)> choose);
    void hide();
    void watch(std::function<void()> callback);
    void refresh(const Editor& editor);
    bool moveVertical(Draft& draft,int direction,bool extend);

private:
    HWND window = nullptr;
    HFONT font = nullptr;
    std::wstring sentence, translation, status, language;
    size_t columns=5;
    RECT lastCaret{};
    std::function<void()> tick;
    std::vector<POINT> positions;
    int sourceTop=38, sourceHeight=32, translationTop=0, translationHeight=0, sourceScroll=0, translationScroll=0, translationContentHeight=0;
    bool ensureWindow();
    CandidateState candidates;
    size_t caretPosition = 0, selectionStart = 0, selectionEnd = 0;
    std::vector<RECT> boxes;
    std::function<void(size_t)> select;
    int scale = 96, width = 500, height = 160;
    int px(int value) const { return MulDiv(value,scale,96); }
    void layout(HDC dc, int maxWidth);
    void paint();
    static LRESULT CALLBACK procedure(HWND window, UINT message, WPARAM wParam, LPARAM lParam);
};
}
