#pragma once
#include "platform.h"
#include <condition_variable>
#include <mutex>
#include <thread>
#include <optional>
namespace sayspan {
struct TranslationReply { unsigned revision=0; bool success=false; std::wstring target,text; };
// One worker per service. No network, credentials, or waits run on the TSF thread.
class TranslationBridge {
public:
    TranslationBridge();
    ~TranslationBridge();
    void submit(unsigned revision,std::wstring language,std::wstring text);
    void cancel();
    std::optional<TranslationReply> take();
    static void launch(bool settings=false);
private:
    std::mutex mutex;
    std::condition_variable wake;
    std::atomic<bool> stopping{false};
    std::atomic<unsigned> serial{0};
    struct Request { unsigned serial,revision; std::wstring language,text; };
    std::optional<Request> queued;
    std::optional<TranslationReply> reply;
    std::thread worker;
    void run();
    bool transfer(HANDLE pipe,void* data,DWORD size,bool write,unsigned request);
    bool frame(HANDLE pipe,std::wstring& value,bool write,unsigned request);
};
}
