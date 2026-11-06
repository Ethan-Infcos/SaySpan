#include "rime_engine.h"
#include <iostream>
namespace sayspan{HINSTANCE module=nullptr;std::atomic<long> objects{0};}
int wmain(int argc,wchar_t** argv){
    using namespace sayspan; module=GetModuleHandleW(nullptr);
    try{
        if(argc==4 && std::wstring(argv[1])==L"--deploy")return InitializeRime(argv[2],argv[3],true)?0:1;
        if(argc!=2)return 2;
        bool sandbox=std::wstring(argv[1])==L"--sandbox";
        if(sandbox && !InAppContainer())return 3;
        if(!sandbox && !InitializeRime(ModuleFolder()/L"data",argv[1],false))throw std::runtime_error("InitializeRime failed");
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
        auto outcome=editor.process({Key::SwitchLanguage,{}});
        if(!outcome.commit||editor.draft.text!=u"你好")throw std::runtime_error("Language switch did not confirm source");
        editor.reset();engine.type('s');auto first=engine.state();engine.page(false);auto second=engine.state();
        if(first.candidates==second.candidates)throw std::runtime_error("candidate paging failed");
        engine.clear();engine.expand(true,5);engine.type('s');auto expanded=engine.state();
        if(expanded.candidates.size()!=15)throw std::runtime_error("expanded candidate grid does not contain 3 rows of 5");
        RimeEngine japanese(L"ja");for(char c:std::string("nihon"))japanese.type(c);
        auto ja=japanese.state();if(ja.candidates.empty())throw std::runtime_error("Japanese candidates unavailable");
        bool kana=false;for(const auto& value:ja.candidates)for(auto c:value)kana=kana || c>127;
        if(!kana)throw std::runtime_error("Japanese engine returned only Latin letters");
        RimeEngine traditional(L"zh-Hant");for(char c:std::string("hanyu"))traditional.type(c);
        auto tr=traditional.state();bool converted=false;for(const auto& value:tr.candidates)converted=converted || value.find(u'漢')!=std::u16string::npos;
        if(!converted)throw std::runtime_error("Traditional Chinese conversion unavailable");
        std::cout<<"Native Rime composition checks passed\n";return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
