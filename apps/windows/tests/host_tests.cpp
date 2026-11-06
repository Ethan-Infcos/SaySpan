// Runs only in an isolated Windows CI session. No global keyboard injection.
#include "platform.h"
#include <richedit.h>
#include <iostream>
#include <stdexcept>
using namespace sayspan;
void verify(HRESULT hr,const char* message){if(FAILED(hr)){std::cerr<<message<<": HRESULT 0x"<<std::hex<<static_cast<unsigned long>(hr)<<"\n";throw std::runtime_error(message);}}
void pump(){MSG message{};while(PeekMessageW(&message,nullptr,0,0,PM_REMOVE)){TranslateMessage(&message);DispatchMessageW(&message);}}
void settle(){for(int i=0;i<100;++i){pump();Sleep(10);}}
int wmain(int argc,wchar_t** argv){
    CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);
    try {
        HMODULE rich=LoadLibraryW(L"Msftedit.dll");if(!rich)throw std::runtime_error("RichEdit unavailable");
        ComPtr<ITfThreadMgr> manager;verify(CoCreateInstance(CLSID_TF_ThreadMgr,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&manager)),"thread manager");
        TfClientId id;verify(manager->Activate(&id),"activate thread");
        HWND window=CreateWindowExW(0,L"STATIC",L"SaySpan isolated host test",WS_OVERLAPPEDWINDOW|WS_VISIBLE,100,100,800,400,nullptr,nullptr,GetModuleHandle(nullptr),nullptr);
        HWND edit=CreateWindowExW(0,MSFTEDIT_CLASS,L"",WS_CHILD|WS_VISIBLE|ES_MULTILINE,0,0,750,300,window,nullptr,GetModuleHandle(nullptr),nullptr);
        SendMessageW(edit,EM_SETEDITSTYLE,SES_USECTF,SES_USECTF);
        SetForegroundWindow(window);SetActiveWindow(window);SetFocus(edit);settle();
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
        settle();
        TF_INPUTPROCESSORPROFILE active{};
        verify(profiles->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD,&active),"active keyboard profile");
        if(active.clsid!=ServiceId || active.guidProfile!=ProfileId)throw std::runtime_error("SaySpan did not become the test-process keyboard");
        ComPtr<ITfKeystrokeMgr> keys; verify(manager.As(&keys),"keystroke manager");
        BYTE previous[256]{};GetKeyboardState(previous);BYTE keyboard[256]{};SetKeyboardState(keyboard);
        auto key=[&](WPARAM vk){
            SetKeyboardState(keyboard);
            BOOL eat=FALSE; LPARAM flags=static_cast<LPARAM>(MapVirtualKeyW(static_cast<UINT>(vk),MAPVK_VK_TO_VSC))<<16;
            verify(keys->TestKeyDown(vk,flags,&eat),"test key");
            if(!eat)throw std::runtime_error("key was not accepted");
            verify(keys->KeyDown(vk,flags,&eat),"key down");pump();
        };
        auto hostKey=[&](WPARAM vk){
            SetKeyboardState(keyboard);BOOL eat=TRUE;
            LPARAM flags=(static_cast<LPARAM>(MapVirtualKeyW(static_cast<UINT>(vk),MAPVK_VK_TO_VSC))<<16)|1;
            verify(keys->TestKeyDown(vk,flags,&eat),"test native key");
            if(eat)throw std::runtime_error("SaySpan claimed a host key at the test phase");
            MSG message{};message.hwnd=edit;message.message=WM_KEYDOWN;message.wParam=vk;message.lParam=flags;
            TranslateMessage(&message);DispatchMessageW(&message);pump();
        };
        auto shiftDown=[&]{keyboard[VK_SHIFT]=0x80;hostKey(VK_SHIFT);};
        auto shiftUp=[&]{
            keyboard[VK_SHIFT]=0;SetKeyboardState(keyboard);BOOL eat=FALSE;
            verify(keys->TestKeyUp(VK_SHIFT,0,&eat),"test Shift release");
            if(eat)verify(keys->KeyUp(VK_SHIFT,0,&eat),"Shift release");
            else SendMessageW(edit,WM_KEYUP,VK_SHIFT,0);
            pump();
        };
        auto directEnglish=[&]{SetKeyboardState(keyboard);BOOL eat=TRUE;keys->TestKeyDown('H',0,&eat);return !eat;};
        if(!directEnglish())throw std::runtime_error("initial mode is not direct English");
        shiftDown();shiftUp();
        for(wchar_t c:std::wstring(L"NIHAO"))key(c);
        key(VK_SPACE);key(VK_RETURN);
        wchar_t output[256]{};GetWindowTextW(edit,output,256);
        if(std::wstring(output)!=L"你好")throw std::runtime_error("TSF host text differs from committed sentence");
        key('N');key('I');shiftDown();shiftUp();
        GetWindowTextW(edit,output,256);if(wcslen(output)<3)throw std::runtime_error("Shift switch dropped draft");
        if(!directEnglish())throw std::runtime_error("Shift did not restore direct English");
        keyboard[VK_CAPITAL]=1;
        if(!directEnglish())throw std::runtime_error("Caps Lock changed the language");
        keyboard[VK_CAPITAL]=0;
        shiftDown();
        // A Shift+letter chord must pass through and must not toggle the language.
        GetWindowTextW(edit,output,256);std::wstring before=output;
        hostKey('A');hostKey('B');hostKey('C');hostKey('1');shiftUp();
        GetWindowTextW(edit,output,256);
        if(std::wstring(output)!=before+L"ABC!")throw std::runtime_error("Shift letters/punctuation did not reach the host as ABC!");
        if(!directEnglish())throw std::runtime_error("Shift letter chord changed the language");
        shiftDown();shiftUp();key('N');key('I');key('H');key('A');key('O');key(VK_SPACE);
        shiftDown();key(VK_LEFT);shiftUp();key(VK_BACK);key(VK_RETURN);
        // Selection with Shift remains Chinese mode; the next spelling is still consumed.
        key('H');key('A');key('O');key(VK_SPACE);key(VK_RETURN);
        if(argc>1 && std::wstring(argv[1])==L"--translation") {
            key('N');key('I');key('H');key('A');key('O');key(VK_SPACE);
            settle();settle();key(VK_TAB);settle();
            GetWindowTextW(edit,output,256);
            if(std::wstring(output).find(L"__TRANSLATED__")==std::wstring::npos)throw std::runtime_error("Companion translation did not reach the host through Tab");
        }
        SetKeyboardState(previous);
        profiles->DeactivateProfile(TF_PROFILETYPE_INPUTPROCESSOR,ProfileLanguage,ServiceId,ProfileId,nullptr,TF_IPPMF_FORPROCESS);
        languages->ChangeCurrentLanguage(originalLanguage);pump();DestroyWindow(window);manager->Deactivate();
        std::cout<<"Native RichEdit TSF insertion, Shift switching, chords and Caps Lock checks passed\n";return 0;
    }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
