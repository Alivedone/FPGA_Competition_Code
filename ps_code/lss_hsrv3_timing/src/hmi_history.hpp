#pragma once
#include "core.hpp"
#include <functional>

namespace v3::hmi {
struct Request { uint8_t command=0, argument=0; };
// Accept only the seven-byte project request frame; other bytes (including ACKs)
// are skipped. Fragmentation and multiple frames per read are both supported.
class RequestParser {
    Bytes buffer_;
public:
    std::vector<Request> feed(const unsigned char* bytes,size_t size);
};

struct ScreenPacket { std::string body; }; // UTF-8 text, without FF terminator
std::string safe_text(const std::string&,size_t max_codepoints=32);
std::string text_command(const std::string& control,const std::string& text);
std::string fixed(double n,int digits=2);

// Append-only snapshots; only offsets/IDs are retained in RAM. Old records remain
// queryable after restart. Updates append a new snapshot with the same ID.
class History {
    std::filesystem::path path_;
    std::shared_ptr<void> writer_lock_;
    std::ofstream append_;
    std::map<uint64_t,std::streamoff> offsets_;
    uint64_t last_=0;
public:
    explicit History(const std::filesystem::path&);
    uint64_t add(Json record);
    void put(uint64_t id,Json record);
    Json get(uint64_t id) const;
    uint64_t last_id() const{return last_;}
    size_t count(uint64_t anchor=UINT64_MAX) const;
    std::vector<uint64_t> page(uint64_t anchor,size_t page_index,size_t size=5) const;
};

class Model {
    History& history_;
    std::string session_,model_id_,task_,state_="等待数据",hint_="暂无新结果";
    uint64_t generation_=0,latest_=0,selected_=0,anchor_=0;
    size_t page_index_=0;
    std::vector<uint64_t> row_ids_,task_records_;
    std::map<uint64_t,Json> pending_window_;
    std::map<uint64_t,uint64_t> window_records_;
    std::string page_="main";
    bool dirty_=true, history_dirty_=false, fatal_=false;
    Clock::time_point last_result_=Clock::now();
    void patch_task(const char* key,const Json& value);
public:
    Model(History&,std::string model_id);
    void ingest(const Json&);
    bool request(Request); // false for invalid/stale selection
    std::vector<std::string> render();
    std::vector<std::string> notice(); // new-result badge without reordering rows
    bool dirty() const{return dirty_;}
    bool notice_dirty() const{return history_dirty_;}
    void refresh(){dirty_=true;}
    const std::string& current_page() const{return page_;}
    size_t current_index() const{return page_index_;}
    uint64_t selected_id() const{return selected_;}
    uint64_t latest_id() const{return latest_;}
};
}
