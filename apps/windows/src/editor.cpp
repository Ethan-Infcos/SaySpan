#include "editor.h"
namespace sayspan {
namespace {
bool high(char16_t c) { return c >= 0xd800 && c <= 0xdbff; }
bool low(char16_t c) { return c >= 0xdc00 && c <= 0xdfff; }
size_t previous(const std::u16string& s, size_t p) {
    if (!p) return 0;
    --p;
    if (p && low(s[p]) && high(s[p-1])) --p;
    return p;
}
size_t next(const std::u16string& s, size_t p) {
    if (p >= s.size()) return s.size();
    if (high(s[p]) && p+1 < s.size() && low(s[p+1])) return p+2;
    return p+1;
}
}
void Draft::save() {
    if (history.size() >= 100) history.erase(history.begin());
    history.push_back({text, caret, anchor});
}
void Draft::insert(const std::u16string& value) {
    if (text.size() - (end()-start()) + value.size() > 8192) return;
    if (value.empty() && !selected()) return;
    save();
    auto position = start();
    text.replace(position, end()-position, value);
    caret = anchor = position + value.size();
}
void Draft::erase(bool backward) {
    if (selected()) { insert(u""); return; }
    if ((backward && !caret) || (!backward && caret == text.size())) return;
    save();
    size_t begin = backward ? previous(text, caret) : caret;
    size_t end = backward ? caret : next(text, caret);
    text.erase(begin, end - begin);
    caret = anchor = begin;
}
void Draft::move(int direction, bool extend) {
    if (!extend && selected()) caret = direction < 0 ? start() : end();
    else caret = direction < 0 ? previous(text, caret) : next(text, caret);
    if (!extend) anchor = caret;
}
void Draft::home(bool extend) { caret = 0; if (!extend) anchor = caret; }
void Draft::finish(bool extend) { caret = text.size(); if (!extend) anchor = caret; }
void Draft::undo() {
    if (history.empty()) return;
    auto s = history.back(); history.pop_back();
    text = std::move(s.text); caret = s.caret; anchor = s.anchor;
}
void Draft::clear() { text.clear(); caret = anchor = 0; history.clear(); }
std::u16string Editor::marked() const {
    return draft.text.substr(0,draft.start()) + engine.state().spelling + draft.text.substr(pending() ? draft.end() : draft.start());
}
size_t Editor::markedCaret() const { return pending() ? draft.start()+engine.state().spelling.size() : draft.caret; }
void Editor::drain() { auto text = engine.takeCommit(); if (!text.empty()) draft.insert(text); }
void Editor::resolve(bool literal) {
    if (!pending()) return;
    if (literal) { auto text = engine.literal(); engine.clear(); draft.insert(text); }
    else { engine.confirm(); drain(); }
}
void Editor::choose(size_t index) { engine.choose(index); drain(); }
Result Editor::process(const Input& input) {
    switch (input.key) {
    case Key::CapsLock: resolve(false); return {false, active(), false};
    case Key::Tab: resolve(false); return {false, active(), false};
    case Key::Enter:
        if (pending()) { resolve(true); return {}; }
        return {active(), active(), false};
    case Key::Escape:
        if (pending()) engine.clear();
        else if (draft.selected()) draft.anchor = draft.caret;
        else return {active(), false, active()};
        return {};
    case Key::Backspace:
        if (pending()) { engine.backspace(); drain(); }
        else draft.erase(true);
        return {};
    case Key::Delete: if (pending()) resolve(true); draft.erase(false); return {};
    case Key::SelectAll: resolve(true); draft.selectAll(); return {};
    case Key::Undo: if (pending()) engine.clear(); else draft.undo(); return {};
    case Key::Left: case Key::Right: case Key::Up: case Key::Down:
        if (pending()) engine.move(input.key == Key::Left || input.key == Key::Up ? -1 : 1);
        else draft.move(input.key == Key::Left || input.key == Key::Up ? -1 : 1, input.shift);
        return {};
    case Key::Home: if (pending()) engine.page(true); else draft.home(input.shift); return {};
    case Key::End: if (pending()) engine.page(false); else draft.finish(input.shift); return {};
    case Key::PageUp: case Key::PageDown: if (pending()) engine.page(input.key == Key::PageUp); return {};
    case Key::Space:
        if (pending()) { auto c = engine.state(); if (!c.candidates.empty()) choose(c.highlighted); else resolve(true); }
        else draft.insert(u" ");
        return {};
    case Key::Text:
        if (marked().size() >= 8192 && !draft.selected()) return {};
        if (input.text.size() == 1) {
            char16_t c = input.text.front();
            if (!input.shift && c >= u'1' && c <= u'5' && pending()) {
                choose(static_cast<size_t>(c-u'1')); return {};
            }
            if (!input.shift && ((c >= u'a' && c <= u'z') || c == u'\'')) {
                engine.type(static_cast<char>(c)); drain(); return {};
            }
        }
        resolve(true);
        draft.insert(input.text);
        return {};
    }
    return {false,false,false};
}
}
