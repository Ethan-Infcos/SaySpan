#include "editor.h"
#include "mode_switch.h"
#include <iostream>
#include <stdexcept>
using namespace sayspan;
static int checks=0;
void check(bool ok,const char* message){++checks;if(!ok)throw std::runtime_error(message);}
class Fake final:public Pinyin {
public:
    CandidateState value; std::u16string committed; int pages=0;
    CandidateState state()const override{return value;}
    void type(char c)override{value.spelling+=char16_t(c);value.candidates={u"你好",u"你号"};}
    void backspace()override{if(!value.spelling.empty())value.spelling.pop_back();if(value.spelling.empty())value={};}
    void choose(size_t i)override{if(i<value.candidates.size()){committed=value.candidates[i];value={};}}
    void move(int d)override{value.highlighted=d>0?1:0;}
    void page(bool back)override{pages+=back?-1:1;}
    std::u16string takeCommit()override{auto s=committed;committed.clear();return s;}
    std::u16string literal()const override{auto s=value.spelling;s.erase(std::remove(s.begin(),s.end(),u'\''),s.end());return s;}
    void confirm()override{choose(value.highlighted);}
    void clear()override{value={};committed.clear();}
};
int main(){try {
    ModeSwitch mode;
    check(!mode.chinese,"Windows defaults to direct English");
    mode.down(100,false);check(mode.up(200),"short Shift tap switches");mode.toggle();check(mode.chinese,"Shift selects Chinese");
    mode.down(300,false);mode.otherKey();check(!mode.up(400),"Shift letter chord does not switch");
    mode.down(500,false);check(!mode.up(1100),"long Shift hold does not switch");
    mode.down(1200,true);check(!mode.up(1300),"Ctrl Shift does not switch");
    mode.down(1400,false);mode.cancelPress();check(!mode.up(1450),"focus change cancels Shift tap");
    Draft d;d.insert(u"A\U0001F600中B");check(d.caret==5,"UTF16 caret");
    d.move(-1,false);d.move(-1,false);d.erase(true);check(d.text==u"A中B","erase complete surrogate");
    d.undo();check(d.text==u"A\U0001F600中B"&&d.caret==3&&d.anchor==3,"undo restores original caret");
    d.move(-1,true);check(d.selection()==u"\U0001F600","select complete surrogate");
    d.insert(u"X");check(d.text==u"AX中B","replace selection");d.selectAll();d.erase(false);check(d.text.empty(),"delete selected sentence");
    d.undo();check(d.text==u"AX中B"&&d.selected(),"undo selected deletion");
    d.clear();d.insert(std::u16string(8192,u'x'));d.insert(u"y");check(d.text.size()==8192,"bounded draft");
    Fake f;Editor e(f);for(char16_t c:std::u16string(u"nihao"))e.process({Key::Text,{c}});
    check(e.pending()&&e.marked()==u"nihao","pending pinyin");
    e.process({Key::Down,{}});check(e.candidates().highlighted==1&&e.draft.caret==0,"arrows belong to candidates");
    e.process({Key::Space,{}});check(e.draft.text==u"你号"&&!e.pending(),"space chooses highlighted");
    e.process({Key::Left,{},true});check(e.draft.selection()==u"号","shift selection after resolving");
    e.process({Key::Text,u"CAD",true});check(e.draft.text==u"你CAD","mixed Latin replaces selection");
    e.process({Key::Text,u"n"});e.process({Key::Text,u"'"});e.process({Key::Text,u"i"});
    e.process({Key::Enter,{}});check(e.draft.text==u"你CADni"&&!e.pending(),"enter preserves raw letters without separators");
    auto r=e.process({Key::Enter,{}});check(r.commit&&r.handled,"enter commits resolved sentence");
    e.reset();e.process({Key::Text,u"n"});r=e.process({Key::SwitchLanguage,{}});
    check(r.commit&&!r.handled&&e.draft.text==u"你好","Language switch confirms source before changing mode");
    e.reset();e.process({Key::Text,u"n"});e.process({Key::PageDown,{}});check(f.pages==1,"page forwarded");
    e.process({Key::Escape,{}});check(!e.active(),"clear pending closes panel");
    e.draft.insert(u"Keep");e.process({Key::SelectAll,{}});check(e.draft.selection()==u"Keep","draft select all");
    e.process({Key::Backspace,{}});check(!e.active(),"empty sentence closes");
    e.process({Key::Undo,{}});check(e.active()&&e.draft.text==u"Keep","undo restores editor draft");
    std::cout<<checks<<" editor checks passed\n";return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
