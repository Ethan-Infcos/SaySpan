#pragma once
#include "platform.h"
#include <memory>
namespace sayspan {
bool InitializeRime(const std::filesystem::path& data, const std::filesystem::path& user, bool deploy);
bool RimeInitialized();
class RimeEngine final : public Pinyin {
public:
    RimeEngine();
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
private:
    uintptr_t session = 0;
};
}
