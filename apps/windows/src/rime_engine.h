#pragma once
#include "platform.h"
#include <memory>
namespace sayspan {
bool InitializeRime(const std::filesystem::path& data, const std::filesystem::path& user, bool deploy);
bool RimeInitialized();
class RimeEngine final : public Pinyin {
public:
    explicit RimeEngine(const std::wstring& language = L"zh");
    ~RimeEngine() override;
    CandidateState state() const override;
    void type(char letter) override;
    void backspace() override;
    void choose(size_t index) override;
    void move(int delta) override;
    void page(bool backward) override;
    std::u16string takeCommit() override;
    std::u16string literal() const override;
    void confirm() override;
    void clear() override;
    void expand(bool expanded,size_t columns) override;
private:
    uintptr_t session = 0;
    std::wstring language;
    size_t pageStart=0, highlighted=0, pageSize=5;
    mutable bool dirty=true;
    mutable std::vector<std::pair<size_t,std::u16string>> pool;
    void refresh() const;
    void changed() { dirty=true; pageStart=highlighted=0; }
    void remember(const std::u16string& candidate);

};
}
