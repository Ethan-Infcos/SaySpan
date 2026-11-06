#pragma once
#include <algorithm>
#include <cstddef>
#include <string>
#include <vector>

namespace sayspan {
struct CandidateState {
    std::u16string spelling;
    std::vector<std::u16string> candidates;
    size_t highlighted = 0;
    bool previous = false;
    bool next = false;
};
class Pinyin {
public:
    virtual ~Pinyin() = default;
    virtual CandidateState state() const = 0;
    virtual void type(char letter) = 0;
    virtual void backspace() = 0;
    virtual void choose(size_t index) = 0;
    virtual void move(int delta) = 0;
    virtual void page(bool backward) = 0;
    virtual std::u16string takeCommit() = 0;
    virtual std::u16string literal() const = 0;
    virtual void confirm() = 0;
    virtual void clear() = 0;
};
class Draft {
public:
    std::u16string text;
    size_t caret = 0;
    size_t anchor = 0;
    size_t start() const { return std::min(caret, anchor); }
    size_t end() const { return std::max(caret, anchor); }
    bool selected() const { return caret != anchor; }
    std::u16string selection() const { return text.substr(start(), end() - start()); }
    void insert(const std::u16string& value);
    void erase(bool backward);
    void move(int direction, bool extend);
    void home(bool extend);
    void finish(bool extend);
    void selectAll() { anchor = 0; caret = text.size(); }
    void undo();
    void clear();
private:
    struct State { std::u16string text; size_t caret; size_t anchor; };
    std::vector<State> history;
    void save();
};
enum class Key { Text, Left, Right, Up, Down, Home, End, Backspace, Delete,
                 Space, Enter, Tab, Escape, PageUp, PageDown, SwitchLanguage, SelectAll, Undo };
struct Input { Key key; std::u16string text; bool shift = false; };
struct Result { bool handled = true; bool commit = false; bool cancel = false; };
class Editor {
public:
    explicit Editor(Pinyin& engine) : engine(engine) {}
    Draft draft;
    bool pending() const { return !engine.state().spelling.empty(); }
    bool active() const { return !draft.text.empty() || pending(); }
    std::u16string marked() const;
    size_t markedCaret() const;
    CandidateState candidates() const { return engine.state(); }
    Result process(const Input& input);
    void choose(size_t index);
    void resolve(bool literal);
    void reset() { draft.clear(); engine.clear(); }
private:
    Pinyin& engine;
    void drain();
};
}
