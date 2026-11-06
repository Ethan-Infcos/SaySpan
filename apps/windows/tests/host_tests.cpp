// Runs only in an isolated Windows CI session. No global keyboard injection.
#include "platform.h"
#include <richedit.h>
#include <iostream>
#include <stdexcept>
using namespace sayspan;
void verify(HRESULT hr,const char* message){if(FAILED(hr)){std::cerr<<message<<": HRESULT 0x"<<std::hex<<static_cast<unsigned long>(hr)<<"\n";throw std::runtime_error(message);}}
void pump(){MSG message{};while(PeekMessageW(&message,nullptr,0,0,PM_REMOVE)){TranslateMessage(&message);DispatchMessageW(&message);}}
int wmain(){
    CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
    try {
        HMODULE rich=LoadLibraryW(L"Msftedit.dll");if(!rich)throw std::runtime_error("RichEdit unavailable");
        ComPtr<ITfThreadMgr> manager;verify(CoCreateInstance(CLSID_TF_ThreadMgr,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&manager)),"thread manager");
        TfClientId id;verify(manager->Activate(&id),"activate thread");
        HWND window=CreateWindowExW(0,L"STATIC",L"SaySpan isolated host test",WS_OVERLAPPEDWINDOW|WS_VISIBLE,100,100,800,400,nullptr,nullptr,GetModuleHandle(nullptr),nullptr);
        HWND edit=CreateWindowExW(0,MSFTEDIT_CLASS,L"",WS_CHILD|WS_VISIBLE|ES_MULTILINE,0,0,750,300,window,nullptr,GetModuleHandle(nullptr),nullptr);
        SendMessageW(edit,EM_SETEDITSTYLE,SES_USECTF,SES_USECTF);
        SetForegroundWindow(window);SetFocus(edit);pump();
        ComPtr<ITfDocumentMgr> document;verify(manager->GetFocus(&document),"focused document");
        if(!document)throw std::runtime_error("RichEdit did not expose a TSF document");
        ComPtr<ITfContext> context;verify(document->GetTop(&context),"top context");
        ComPtr<ITfInputProcessorProfiles> languages;
        verify(CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&languages)),"language manager");
        LANGID originalLanguage=0; languages->GetCurrentLanguage(&originalLanguage);
        verify(languages->ChangeCurrentLanguage(ProfileLanguage),"select test-thread language");
        ComPtr<ITfInputProcessorProfileMgr> profiles;
        verify(languages.As(&profiles),"profile manager");
        verify(profiles->ActivateProfile(TF_PROFILETYPE_INPUTPROCESSOR,ProfileLanguage,ServiceId,ProfileId,nullptr,
            TF_IPPMF_FORPROCESS|TF_IPPMF_ENABLEPROFILE),"activate test-process profile");
        pump();
        ComPtr<ITfKeystrokeMgr> keys; verify(manager.As(&keys),"keystroke manager");
        BYTE previous[256]{};GetKeyboardState(previous);BYTE keyboard[256]{};keyboard[VK_CAPITAL]=1;SetKeyboardState(keyboard);
        auto key=[&](WPARAM vk){BOOL eat=FALSE;verify(keys->TestKeyDown(vk,0,&eat),"test key");if(!eat)throw std::runtime_error("key was not accepted");verify(keys->KeyDown(vk,0,&eat),"key down");pump();};
        for(wchar_t c:std::wstring(L"NIHAO"))key(c);
        key(VK_SPACE);key(VK_RETURN);
        wchar_t output[256]{};GetWindowTextW(edit,output,256);
        if(std::wstring(output)!=L"你好")throw std::runtime_error("TSF host text differs from committed sentence");
        key('N');key('I');key(VK_CAPITAL);
        GetWindowTextW(edit,output,256);if(wcslen(output)<3)throw std::runtime_error("Caps Lock dropped draft");
        keyboard[VK_CAPITAL]=0;SetKeyboardState(keyboard);BOOL eat=TRUE;keys->TestKeyDown('H',0,&eat);
        if(eat)throw std::runtime_error("English mode did not pass through");
        SetKeyboardState(previous);
        profiles->DeactivateProfile(TF_PROFILETYPE_INPUTPROCESSOR,ProfileLanguage,ServiceId,ProfileId,nullptr,TF_IPPMF_FORPROCESS);
        languages->ChangeCurrentLanguage(originalLanguage);pump();DestroyWindow(window);manager->Deactivate();
        std::cout<<"Native RichEdit TSF insertion and Caps Lock checks passed\n";return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
