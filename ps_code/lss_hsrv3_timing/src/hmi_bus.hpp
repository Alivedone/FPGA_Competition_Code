#pragma once
#include "core.hpp"

namespace v3 {
struct HmiSink {
    virtual void post(const Json&) noexcept=0;
    virtual ~HmiSink()=default;
};
// Installed before Service starts; removed after Service and its monitor drain.
inline std::atomic<HmiSink*> hmi_sink{nullptr};
inline void hmi_publish(const Json& event) noexcept {
    if(auto* sink=hmi_sink.load(std::memory_order_acquire))sink->post(event);
}
}
