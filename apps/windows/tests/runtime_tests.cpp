#include "rime_engine.h"
#include <iostream>
namespace sayspan{HINSTANCE module=nullptr;std::atomic<long> objects{0};}
int wmain(int argc,wchar_t** argv){
    using namespace sayspan; module=GetModuleHandleW(nullptr);
    try{
        if(argc==4 && std::wstring(argv[1])==L"--deploy")return InitializeRime(argv[2],argv[3],true)?0:1;
        if(argc!=2)return 2;
        if(!InitializeRime(ModuleFolder()/L"data",argv[1],false))throw std::runtime_error("InitializeRime failed");
        RimeEngine engine;Editor editor(engine);
        for(char16_t c:std::u16string(u"nihao"))editor.process({Key::Text,{c}});
        auto candidates=editor.candidates();
        if(candidates.candidates.empty()||candidates.candidates.front()!=u"你好")throw std::runtime_error("nihao candidate missing");
        editor.process({Key::Space,{}});
        if(editor.draft.text!=u"你好"||editor.pending())throw std::runtime_error("candidate not committed to sentence");
        editor.process({Key::Text,u"CAD",true});
        for(char16_t c:std::u16string(u"ceshi"))editor.process({Key::Text,{c}});
        editor.process({Key::Enter,{}});
        if(editor.draft.text!=u"你好CADceshi")throw std::runtime_error("mixed sentence mismatch");
        editor.reset();for(char16_t c:std::u16string(u"nihao"))editor.process({Key::Text,{c}});
        auto outcome=editor.process({Key::CapsLock,{}});
        if(!outcome.commit||editor.draft.text!=u"你好")throw std::runtime_error("Caps Lock did not confirm source");
        editor.reset();engine.type('s');auto first=engine.state();engine.page(false);auto second=engine.state();
        if(first.candidates==second.candidates)throw std::runtime_error("candidate paging failed");
        std::cout<<"Native Rime composition checks passed\n";return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
