#pragma once
#include <cstdint>
namespace sayspan {
// Windows convention: a short, unmodified Shift tap changes the input language.
// Shift used in a chord, or held for longer than 500 ms, never changes the mode.
class ModeSwitch {
public:
    bool chinese = false;
    bool pressed = false;
    bool chord = false;
    void down(uint64_t time, bool modified) {
        if(pressed) return;
        pressed = true; chord = modified; started = time;
    }
    void otherKey() { if(pressed) chord = true; }
    bool isTap(uint64_t time) const {
        return pressed && !chord && time >= started && time-started <= 500;
    }
    bool up(uint64_t time) {
        bool tap = isTap(time);
        pressed = false; chord = false; return tap;
    }
    void cancelPress() { pressed = chord = false; }
    void toggle() { chinese = !chinese; }
private:
    uint64_t started = 0;
};
}
