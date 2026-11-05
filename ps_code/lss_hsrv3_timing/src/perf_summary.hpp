#pragma once
#include "core.hpp"
#include "hmi_bus.hpp"
#include <type_traits>
#include <utility>

namespace v3 {
// Service worker and hardware calls run on the same thread. Never sent over TCP.
struct PerfContext { std::string task_id; uint64_t window_index=0, start_frame=0; };
inline thread_local PerfContext perf_context;
inline std::mutex perf_log_mutex;
class PerfSummary {
    Clock::time_point started_=Clock::now();
    Json fields_=Json::object(), stages_=Json::object(), details_=Json::object();
    std::string active_; bool finished_=false;
public:
    explicit PerfSummary(const char* scope):fields_({{"scope",scope},{"revision","timing_v1"},
        {"task_id",perf_context.task_id},{"window_index",perf_context.window_index},
        {"start_frame",perf_context.start_frame},{"clock","steady_clock"}}) {}
    void set(const char* key,const Json& value){fields_[key]=value;}
    void zero(const char* stage){stages_[stage]=0.0;}
    template<class F> auto run(const char* stage,F&& fn) {
        active_=stage;const auto start=Clock::now();
        auto record=[&]{stages_[stage]=stages_.value(stage,0.0)+
            std::chrono::duration<double,std::milli>(Clock::now()-start).count();};
        try {
            if constexpr(std::is_void_v<std::invoke_result_t<F>>) {
                std::forward<F>(fn)();record();active_.clear();
            } else {
                auto result=std::forward<F>(fn)();record();active_.clear();return result;
            }
        } catch(...) {record();throw;}
    }
    // Details are nested within a stage, never added to the disjoint stage sum.
    template<class F> auto detail(const char* name,F&& fn) {
        const auto start=Clock::now();
        auto record=[&]{details_[name]=details_.value(name,0.0)+std::chrono::duration<double,std::milli>(Clock::now()-start).count();};
        try {
            if constexpr(std::is_void_v<std::invoke_result_t<F>>) {std::forward<F>(fn)();record();}
            else {auto result=std::forward<F>(fn)();record();return result;}
        }catch(...){record();fields_["failed_detail"]=name;throw;}
    }
    void finish(bool success) noexcept {
        if(finished_)return;finished_=true;
        try {
            // Sample before JSON formatting, mutex wait and summary output.
            fields_["total_ms"]=std::chrono::duration<double,std::milli>(Clock::now()-started_).count();
            fields_["success"]=success;fields_["stages_ms"]=stages_;
            if(!details_.empty())fields_["details_ms"]=details_;
            if(!success)fields_["failed_stage"]=active_;
            double sum=0;for(auto it=stages_.begin();it!=stages_.end();++it)sum+=it.value().get<double>();
            fields_["unassigned_ms"]=fields_["total_ms"].get<double>()-sum;
            std::lock_guard<std::mutex> guard(perf_log_mutex);
            std::cerr<<"V3_PERF "<<fields_.dump()<<'\n';
            hmi_publish(fields_);
        } catch(...) { /* Logging must not replace hardware fault handling. */ }
    }
    ~PerfSummary(){finish(false);}
};
}
