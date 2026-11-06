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
private:
    HWND window = nullptr;
    HFONT font = nullptr;
    std::wstring sentence;
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
