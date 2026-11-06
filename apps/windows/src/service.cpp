#include "platform.h"
#include "panel.h"
#include "rime_engine.h"
#include <functional>
#include <initguid.h>
#include <inputscope.h>
#include <memory>
#include <new>
#include <optional>

namespace sayspan {
HINSTANCE module = nullptr;
std::atomic<long> objects{0};
// Process-local counters for the native test harness; never record text or key values.
static DWORD diagnostics[5]{};

// Edit sessions own the service until Windows grants the document write lock.
class EditSession final : public ITfEditSession {
    std::atomic<ULONG> refs{1};
    ComPtr<IUnknown> owner;
    std::function<HRESULT(TfEditCookie)> action;
public:
    EditSession(IUnknown* owner, std::function<HRESULT(TfEditCookie)> action) : owner(owner), action(std::move(action)) { ++objects; }
    ~EditSession() { --objects; }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER; *out = nullptr;
        if (iid == IID_IUnknown || iid == IID_ITfEditSession) { *out = static_cast<ITfEditSession*>(this); AddRef(); return S_OK; }
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
    ULONG STDMETHODCALLTYPE Release() override { auto count=--refs; if(!count) delete this; return count; }
    HRESULT STDMETHODCALLTYPE DoEditSession(TfEditCookie cookie) override {
        try { return action(cookie); } catch (...) { return E_FAIL; }
    }
};

class Service final : public ITfTextInputProcessorEx, public ITfKeyEventSink,
                      public ITfCompositionSink, public ITfThreadMgrEventSink,
                      public ITfThreadFocusSink {
    std::atomic<ULONG> refs{1};
    ComPtr<ITfThreadMgr> manager;
    TfClientId client = TF_CLIENTID_NULL;
    DWORD managerCookie = TF_INVALID_COOKIE, focusCookie = TF_INVALID_COOKIE;
    ComPtr<ITfContext> context;
    ComPtr<ITfComposition> composition;
    std::unique_ptr<RimeEngine> engine;
    std::unique_ptr<Editor> editor;
    Panel panel;
    std::u16string original;
    bool ending = false;
    bool focused = true;
    unsigned generation = 0;
    unsigned pendingKeys = 0;

    bool active() const { return pendingKeys || (editor && editor->active()); }
    bool allowed(ITfContext* ctx) const {
        if(!ctx) return false;
        ComPtr<ITfCompartmentMgr> compartments;
        if(SUCCEEDED(ctx->QueryInterface(IID_PPV_ARGS(&compartments)))) {
            for(const auto& id : {GUID_COMPARTMENT_KEYBOARD_DISABLED, GUID_COMPARTMENT_EMPTYCONTEXT}) {
                ComPtr<ITfCompartment> compartment; VARIANT value; VariantInit(&value);
                if(SUCCEEDED(compartments->GetCompartment(id,&compartment)) && SUCCEEDED(compartment->GetValue(&value))) {
                    bool disabled=value.vt==VT_I4 && value.lVal!=0; VariantClear(&value); if(disabled) return false;
                }
            }
        }
        HWND window=GetFocus(); wchar_t name[32]{};
        GetClassNameW(window,name,32);
        if((_wcsicmp(name,L"Edit")==0 || _wcsnicmp(name,L"RichEdit",8)==0) && (GetWindowLongPtrW(window,GWL_STYLE)&ES_PASSWORD)) return false;
        return true;
    }
    std::optional<Input> key(WPARAM vk, LPARAM flags) const {
        bool shift=(GetKeyState(VK_SHIFT)&0x8000)!=0;
        bool control=(GetKeyState(VK_CONTROL)&0x8000)!=0;
        bool alt=(GetKeyState(VK_MENU)&0x8000)!=0;
        if(vk==VK_CAPITAL) return active()?std::optional<Input>{{Key::CapsLock,{}}}:std::nullopt;
        if(control || alt || (GetKeyState(VK_LWIN)&0x8000) || (GetKeyState(VK_RWIN)&0x8000)) {
            if(active() && control && !alt) {
                if(vk=='A') return Input{Key::SelectAll,{}};
                if(vk=='Z') return Input{Key::Undo,{}};
            }
            return std::nullopt;
        }
        if(!(GetKeyState(VK_CAPITAL)&1) && !active()) return std::nullopt;
        if(active()) {
            switch(vk) {
            case VK_LEFT:return Input{Key::Left,{},shift}; case VK_RIGHT:return Input{Key::Right,{},shift};
            case VK_UP:return Input{Key::Up,{},shift}; case VK_DOWN:return Input{Key::Down,{},shift};
            case VK_HOME:return Input{Key::Home,{},shift}; case VK_END:return Input{Key::End,{},shift};
            case VK_BACK:return Input{Key::Backspace,{}}; case VK_DELETE:return Input{Key::Delete,{}};
            case VK_SPACE:return Input{Key::Space,{}}; case VK_RETURN:return Input{Key::Enter,{}};
            case VK_TAB:return Input{Key::Tab,{}}; case VK_ESCAPE:return Input{Key::Escape,{}};
            case VK_PRIOR:return Input{Key::PageUp,{}}; case VK_NEXT:return Input{Key::PageDown,{}};
            }
        }
        BYTE state[256]{}; if(!GetKeyboardState(state)) return std::nullopt;
        // Caps Lock chooses the language; Shift still produces uppercase Latin segments.
        state[VK_CAPITAL]=0;
        wchar_t text[8]{};
        int count=ToUnicodeEx(static_cast<UINT>(vk),static_cast<UINT>((flags>>16)&0xff),state,text,8,4,GetKeyboardLayout(0));
        if(count>0 && text[0]>=L' ' && (active() || (text[0]>=L'a' && text[0]<=L'z'))) return Input{Key::Text,utf16(std::wstring(text,count)),shift};
        return std::nullopt;
    }
    HRESULT request(ITfContext* ctx,std::function<HRESULT(TfEditCookie)> action) {
        if(!ctx || client==TF_CLIENTID_NULL) return E_FAIL;
        auto session=new(std::nothrow) EditSession(static_cast<ITfTextInputProcessorEx*>(this),std::move(action));
        if(!session) return E_OUTOFMEMORY;
        HRESULT result=E_FAIL;
        // ASYNCDONTCARE also supports hosts such as Word that reject synchronous writes.
        HRESULT hr=ctx->RequestEditSession(client,session,TF_ES_ASYNCDONTCARE|TF_ES_READWRITE,&result);
        session->Release();
        return FAILED(hr)?hr:result;
    }
    HRESULT start(ITfContext* ctx,TfEditCookie cookie) {
        if(composition) return context.Get()==ctx?S_OK:E_UNEXPECTED;
        ComPtr<ITfInsertAtSelection> insertion;
        HRESULT hr=ctx->QueryInterface(IID_PPV_ARGS(&insertion)); if(FAILED(hr)) return hr;
        ComPtr<ITfRange> range;
        hr=insertion->InsertTextAtSelection(cookie,TF_IAS_QUERYONLY,nullptr,0,&range); if(FAILED(hr)) return hr;
        // Inspect the input scope before reading any selected host text.
        ComPtr<ITfReadOnlyProperty> property;
        if(SUCCEEDED(ctx->GetAppProperty(GUID_PROP_INPUTSCOPE,&property))) {
            VARIANT value; VariantInit(&value);
            if(SUCCEEDED(property->GetValue(cookie,range.Get(),&value)) && value.vt==VT_UNKNOWN && value.punkVal) {
                ComPtr<ITfInputScope> scope;
                if(SUCCEEDED(value.punkVal->QueryInterface(IID_PPV_ARGS(&scope)))) {
                    InputScope* scopes=nullptr; UINT count=0;
                    if(SUCCEEDED(scope->GetInputScopes(&scopes,&count))) {
                        bool password=false;
                        for(UINT i=0;i<count;++i) password=password || scopes[i]==IS_PASSWORD || scopes[i]==IS_NUMERIC_PASSWORD;
                        CoTaskMemFree(scopes);
                        if(password) { VariantClear(&value); return E_ACCESSDENIED; }
                    }
                }
            }
            VariantClear(&value);
        }
        original.clear();
        ComPtr<ITfRange> read; range->Clone(&read);
        wchar_t buffer[1024]; ULONG count=0;
        do { hr=read->GetText(cookie,TF_TF_MOVESTART,buffer,1024,&count); if(FAILED(hr)) return hr;
            if(original.size()+count>8192) return E_FAIL;
            original+=utf16(std::wstring(buffer,count));
        } while(count==1024);
        ComPtr<ITfContextComposition> provider; hr=ctx->QueryInterface(IID_PPV_ARGS(&provider)); if(FAILED(hr)) return hr;
        hr=provider->StartComposition(cookie,range.Get(),this,&composition);
        if(SUCCEEDED(hr) && composition) context=ctx;
        return composition?hr:E_FAIL;
    }
    HRESULT update(TfEditCookie cookie) {
        if(!composition) return E_FAIL;
        ComPtr<ITfRange> range; HRESULT hr=composition->GetRange(&range); if(FAILED(hr)) return hr;
        auto text=wide(editor->marked());
        hr=range->SetText(cookie,0,text.data(),static_cast<LONG>(text.size())); if(FAILED(hr)) return hr;
        ComPtr<ITfRange> caret; range->Clone(&caret); caret->Collapse(cookie,TF_ANCHOR_START);
        LONG shifted=0;
        size_t start=editor->pending()?editor->markedCaret():editor->draft.start();
        size_t end=editor->pending()?start:editor->draft.end();
        caret->ShiftEnd(cookie,static_cast<LONG>(end),&shifted,nullptr);
        caret->ShiftStart(cookie,static_cast<LONG>(start),&shifted,nullptr);
        TF_SELECTION selection{caret.Get(),{TF_AE_END,FALSE}};
        if(!editor->pending() && editor->draft.caret<editor->draft.anchor) selection.style.ase=TF_AE_START;
        hr=context->SetSelection(cookie,1,&selection); if(FAILED(hr)) return hr;
        RECT rect{}; BOOL clipped=FALSE;
        ComPtr<ITfContextView> view; context->GetActiveView(&view);
        if(!view || FAILED(view->GetTextExt(cookie,caret.Get(),&rect,&clipped))) {
            POINT point{}; HWND window=GetFocus();
            if(GetCaretPos(&point) && window) { ClientToScreen(window,&point); rect={point.x,point.y,point.x+1,point.y+22}; }
            else if(window) { GetWindowRect(window,&rect); rect.bottom=rect.top+30; }
        }
        if(focused) {
            ComPtr<ITfContext> target=context; unsigned revision=generation;
            panel.show(*editor,rect,[this,target,revision](size_t candidate) {
                request(target.Get(),[this,target,revision,candidate](TfEditCookie edit) {
                    if(generation!=revision || context.Get()!=target.Get() || !composition) return S_FALSE;
                    editor->choose(candidate); return update(edit);
                });
            });
        }
        return S_OK;
    }
    HRESULT finish(TfEditCookie cookie,bool cancel=false) {
        if(!composition) return S_OK;
        ComPtr<ITfRange> range; HRESULT hr=composition->GetRange(&range); if(FAILED(hr)) return hr;
        editor->resolve(false);
        auto text=wide(cancel?original:editor->draft.text);
        hr=range->SetText(cookie,0,text.data(),static_cast<LONG>(text.size())); if(FAILED(hr)) return hr;
        range->Collapse(cookie,TF_ANCHOR_END);
        TF_SELECTION selection{range.Get(),{TF_AE_END,FALSE}}; context->SetSelection(cookie,1,&selection);
        ending=true; hr=composition->EndComposition(cookie); ending=false;
        if(SUCCEEDED(hr)) { composition.Reset(); context.Reset(); editor->reset(); original.clear(); panel.hide(); ++generation; }
        return hr;
    }
    void finishLater(ITfContext* queuedContext=nullptr) {
        if(!composition && !(pendingKeys && queuedContext)) { panel.hide(); return; }
        ComPtr<ITfContext> target=context?context:ComPtr<ITfContext>(queuedContext); unsigned revision=generation;
        request(target.Get(),[this,target,revision](TfEditCookie cookie) {
            return generation==revision && context.Get()==target.Get()?finish(cookie):S_FALSE;
        });
    }
    bool shortcut(WPARAM vk) const {
        return active() && ((GetKeyState(VK_CONTROL)&0x8000) || (GetKeyState(VK_MENU)&0x8000) ||
            (GetKeyState(VK_LWIN)&0x8000) || (GetKeyState(VK_RWIN)&0x8000)) &&
            vk!=VK_SHIFT && vk!=VK_CONTROL && vk!=VK_MENU && vk!=VK_LWIN && vk!=VK_RWIN;
    }
    bool clipboardKey(WPARAM key) const {
        return active() && (GetKeyState(VK_CONTROL)&0x8000) && !(GetKeyState(VK_MENU)&0x8000) && (key=='C'||key=='X'||key=='V');
    }
    void clipboard(WPARAM key) {
        editor->resolve(true);
        if(!OpenClipboard(GetFocus())) return;
        if(key=='V') {
            HANDLE data=GetClipboardData(CF_UNICODETEXT);
            if(data) {
                auto value=static_cast<const wchar_t*>(GlobalLock(data));
                if(value) {
                    size_t limit=std::min<size_t>(GlobalSize(data)/sizeof(wchar_t),8193),length=0;
                    while(length<limit && value[length]) ++length;
                    if(length<limit && length<=8192) editor->draft.insert(utf16(std::wstring(value,length)));
                    GlobalUnlock(data);
                }
            }
        } else if(editor->draft.selected()) {
            auto text=wide(editor->draft.selection());
            HGLOBAL data=GlobalAlloc(GMEM_MOVEABLE,(text.size()+1)*sizeof(wchar_t));
            if(data) {
                void* buffer=GlobalLock(data);
                if(buffer) {
                    memcpy(buffer,text.c_str(),(text.size()+1)*sizeof(wchar_t)); GlobalUnlock(data);
                    if(EmptyClipboard() && SetClipboardData(CF_UNICODETEXT,data)) { if(key=='X') editor->draft.erase(true); data=nullptr; }
                }
                if(data) GlobalFree(data);
            }
        }
        CloseClipboard();
    }
public:
    Service() { ++objects; }
    ~Service() { --objects; }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid,void** out) override {
        if(!out) return E_POINTER; *out=nullptr;
        if(iid==IID_IUnknown || iid==IID_ITfTextInputProcessor || iid==IID_ITfTextInputProcessorEx) *out=static_cast<ITfTextInputProcessorEx*>(this);
        else if(iid==IID_ITfKeyEventSink) *out=static_cast<ITfKeyEventSink*>(this);
        else if(iid==IID_ITfCompositionSink) *out=static_cast<ITfCompositionSink*>(this);
        else if(iid==IID_ITfThreadMgrEventSink) *out=static_cast<ITfThreadMgrEventSink*>(this);
        else if(iid==IID_ITfThreadFocusSink) *out=static_cast<ITfThreadFocusSink*>(this);
        else return E_NOINTERFACE;
        AddRef(); return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
    ULONG STDMETHODCALLTYPE Release() override { auto count=--refs; if(!count) delete this; return count; }
    HRESULT STDMETHODCALLTYPE Activate(ITfThreadMgr* value,TfClientId id) override { return ActivateEx(value,id,0); }
    HRESULT STDMETHODCALLTYPE ActivateEx(ITfThreadMgr* value,TfClientId id,DWORD flags) override {
        ++diagnostics[0]; diagnostics[1]=flags;
        if(flags&TF_TMAE_SECUREMODE) return E_ACCESSDENIED;
        manager=value; client=id; focused=true;
        ComPtr<ITfKeystrokeMgr> keys; HRESULT hr=manager.As(&keys);
        if(SUCCEEDED(hr)) hr=keys->AdviseKeyEventSink(client,this,TRUE);
        diagnostics[2]=static_cast<DWORD>(hr);
        if(FAILED(hr)) { manager.Reset(); client=TF_CLIENTID_NULL; return hr; }
        ComPtr<ITfSource> source;
        if(SUCCEEDED(manager.As(&source))) {
            source->AdviseSink(IID_ITfThreadMgrEventSink,static_cast<ITfThreadMgrEventSink*>(this),&managerCookie);
            source->AdviseSink(IID_ITfThreadFocusSink,static_cast<ITfThreadFocusSink*>(this),&focusCookie);
        }
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE Deactivate() override {
        finishLater(); panel.hide(); focused=false;
        if(manager) {
            ComPtr<ITfKeystrokeMgr> keys; if(SUCCEEDED(manager.As(&keys))) keys->UnadviseKeyEventSink(client);
            ComPtr<ITfSource> source; if(SUCCEEDED(manager.As(&source))) {
                if(managerCookie!=TF_INVALID_COOKIE) source->UnadviseSink(managerCookie);
                if(focusCookie!=TF_INVALID_COOKIE) source->UnadviseSink(focusCookie);
            }
        }
        managerCookie=focusCookie=TF_INVALID_COOKIE; manager.Reset(); client=TF_CLIENTID_NULL; return S_OK;
    }
    HRESULT STDMETHODCALLTYPE OnSetFocus(BOOL foreground) override { if(!foreground) { focused=false; panel.hide(); } else focused=true; return S_OK; }
    HRESULT STDMETHODCALLTYPE OnTestKeyDown(ITfContext* ctx,WPARAM vk,LPARAM flags,BOOL* eaten) override {
        if(!eaten) return E_POINTER; *eaten=FALSE;
        ++diagnostics[3]; diagnostics[4]=allowed(ctx);
        try { if(allowed(ctx)) { auto input=key(vk,flags); *eaten=clipboardKey(vk) || input.has_value() || shortcut(vk); } } catch(...) {}
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE OnKeyDown(ITfContext* ctx,WPARAM vk,LPARAM flags,BOOL* eaten) override {
        if(!eaten) return E_POINTER; *eaten=FALSE;
        try {
            if(!allowed(ctx)) return S_OK;
            auto input=key(vk,flags); bool clip=clipboardKey(vk);
            if(!input && !clip) { if(active() && vk!=VK_SHIFT && vk!=VK_CONTROL && vk!=VK_MENU) finishLater(ctx); return S_OK; }
            if(!engine) { engine=std::make_unique<RimeEngine>(); editor=std::make_unique<Editor>(*engine); }
            ComPtr<ITfContext> target=ctx;
            ++pendingKeys;
            auto pending=std::shared_ptr<void>(this,[this](void*) { --pendingKeys; });
            HRESULT hr=request(ctx,[this,target,input,clip,vk,pending](TfEditCookie cookie) {
                if(context && context.Get()!=target.Get()) return E_UNEXPECTED;
                HRESULT result=start(target.Get(),cookie); if(FAILED(result)) return result;
                if(clip) clipboard(vk);
                else {
                    auto outcome=editor->process(*input);
                    if(outcome.commit || outcome.cancel) return finish(cookie,outcome.cancel);
                }
                if(!editor->active()) return finish(cookie,input && input->key==Key::Escape);
                ComPtr<ITfDocumentMgr> current, owner;
                if(manager) manager->GetFocus(&current);
                target->GetDocumentMgr(&owner);
                if(!focused || !current || current.Get()!=owner.Get()) return finish(cookie);
                return update(cookie);
            });
            *eaten=SUCCEEDED(hr) && (clip || (input->key!=Key::CapsLock && input->key!=Key::Tab));
        } catch(...) { /* Never propagate exceptions into the application hosting the IME. */ }
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE OnTestKeyUp(ITfContext*,WPARAM,LPARAM,BOOL* eaten) override { if(!eaten)return E_POINTER; *eaten=FALSE; return S_OK; }
    HRESULT STDMETHODCALLTYPE OnKeyUp(ITfContext*,WPARAM,LPARAM,BOOL* eaten) override { if(!eaten)return E_POINTER; *eaten=FALSE; return S_OK; }
    HRESULT STDMETHODCALLTYPE OnPreservedKey(ITfContext*,REFGUID,BOOL* eaten) override { if(!eaten)return E_POINTER; *eaten=FALSE; return S_OK; }
    HRESULT STDMETHODCALLTYPE OnCompositionTerminated(TfEditCookie,ITfComposition* value) override {
        if(!ending && composition.Get()==value) { composition.Reset(); context.Reset(); if(editor)editor->reset(); original.clear(); panel.hide(); ++generation; }
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE OnInitDocumentMgr(ITfDocumentMgr*) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE OnUninitDocumentMgr(ITfDocumentMgr*) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE OnSetFocus(ITfDocumentMgr* current,ITfDocumentMgr*) override {
        if(context) { ComPtr<ITfDocumentMgr> old; context->GetDocumentMgr(&old); if(old.Get()!=current) finishLater(); }
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE OnPushContext(ITfContext*) override { return S_OK; }
    HRESULT STDMETHODCALLTYPE OnPopContext(ITfContext* value) override { if(context.Get()==value)finishLater(); return S_OK; }
    HRESULT STDMETHODCALLTYPE OnSetThreadFocus() override { focused=true; return S_OK; }
    HRESULT STDMETHODCALLTYPE OnKillThreadFocus() override { focused=false; panel.hide(); finishLater(); return S_OK; }
};
class Factory final : public IClassFactory {
    std::atomic<ULONG> refs{1};
public:
    Factory(){++objects;} ~Factory(){--objects;}
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid,void** out) override {
        if(!out)return E_POINTER; *out=nullptr;
        if(iid!=IID_IUnknown && iid!=IID_IClassFactory)return E_NOINTERFACE;
        *out=static_cast<IClassFactory*>(this); AddRef(); return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override{return ++refs;}
    ULONG STDMETHODCALLTYPE Release() override{auto n=--refs;if(!n)delete this;return n;}
    HRESULT STDMETHODCALLTYPE CreateInstance(IUnknown* outer,REFIID iid,void** out) override {
        if(!out)return E_POINTER; *out=nullptr;if(outer)return CLASS_E_NOAGGREGATION;
        auto service=new(std::nothrow) Service; if(!service)return E_OUTOFMEMORY;
        HRESULT hr=service->QueryInterface(iid,out);service->Release();return hr;
    }
    HRESULT STDMETHODCALLTYPE LockServer(BOOL lock) override { if(lock)++objects;else --objects;return S_OK; }
};
}
extern "C" BOOL WINAPI DllMain(HINSTANCE instance,DWORD reason,LPVOID) {
    if(reason==DLL_PROCESS_ATTACH){sayspan::module=instance;DisableThreadLibraryCalls(instance);}return TRUE;
}
extern "C" HRESULT WINAPI DllCanUnloadNow(){return !sayspan::objects && !sayspan::RimeInitialized()?S_OK:S_FALSE;}
extern "C" HRESULT WINAPI DllGetClassObject(REFCLSID clsid,REFIID iid,void** out){
    if(!out)return E_POINTER;*out=nullptr;if(clsid!=sayspan::ServiceId)return CLASS_E_CLASSNOTAVAILABLE;
    auto factory=new(std::nothrow)sayspan::Factory;if(!factory)return E_OUTOFMEMORY;
    HRESULT hr=factory->QueryInterface(iid,out);factory->Release();return hr;
}

extern "C" void WINAPI SaySpanTestState(DWORD* output) { if(output) for(int i=0;i<5;++i)output[i]=sayspan::diagnostics[i]; }
