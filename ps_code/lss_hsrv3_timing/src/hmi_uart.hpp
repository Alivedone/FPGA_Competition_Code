#pragma once
#include "hmi_bus.hpp"
#include "hmi_history.hpp"

namespace v3::hmi {
struct Options {
    std::string device;
    unsigned baud=115200;
    std::filesystem::path history="runtime_evidence/hmi_history.jsonl";
    std::filesystem::path dry_run;
};
// The only service-facing calls are post/start-by-construction/stop-by-destruction.
// Serial I/O and persistent history writes happen solely in the worker thread.
class Runtime final:public HmiSink {
    struct Impl;
    std::unique_ptr<Impl> impl_;
public:
    Runtime(Options,std::string model_id);
    ~Runtime();
    void post(const Json&) noexcept override;
    bool healthy() const noexcept;
    void stop();
};
std::string encode_gb2312(const std::string& utf8);

// Unified decoder: request arguments must never be mistaken for status ACKs.
struct WireEvents {std::vector<Request> requests;std::vector<uint8_t> status;bool boot=false;};
class WireDecoder {
    Bytes buffer_;
public:
    WireEvents feed(const unsigned char*,size_t);
};
}
