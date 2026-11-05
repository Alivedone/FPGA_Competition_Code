#pragma once
#include "core.hpp"
#include <icraft-xrt/core/session.h>

namespace v3 {
// SJP: preserve synchronization and callback sequence checks. Build verbose
// tracing data only when it will actually be emitted.
class RuntimeTrace {
    bool verbose_,sync_each_;
    uint64_t timeout_;
    std::ostream& log_;
    Clock::time_point started_;
    std::map<int64_t,Clock::time_point> op_start_;
public:
    uint64_t sequence=0,pre_count=0,post_count=0;
    std::vector<int64_t> pre_ids,post_ids;
    RuntimeTrace(bool verbose,bool sync_each,uint64_t timeout,std::ostream& log=std::cerr)
        :verbose_(verbose),sync_each_(sync_each),timeout_(timeout),log_(log){}
    static double ms(Clock::time_point start){return std::chrono::duration<double,std::milli>(Clock::now()-start).count();}
    void event(const char* stage,Json data=Json::object()) {
        if(!verbose_)return;
        data["stage"]=stage;data["sequence"]=sequence;
        log_<<"V3_RUNTIME_TRACE "<<data.dump()<<std::endl;
    }
    void begin(){
        ++sequence;pre_count=post_count=0;pre_ids.clear();post_ids.clear();op_start_.clear();
        if(verbose_){started_=Clock::now();event("begin",{{"sync_each_op",sync_each_}});}
    }
    void attach(icraft::xrt::Session& session) {
        session.setPreCallBack([this](const auto&,const auto& op,const auto&,auto&){
            auto id=op->op_id;++pre_count;pre_ids.push_back(id);
            if(verbose_){op_start_[id]=Clock::now();event("op_pre",{{"op_id",id},{"name",op->name}});}
        });
        session.setPostCallBack([this](const auto&,const auto& op,const auto&,auto& tensors){
            auto id=op->op_id;
            // Keep all readiness and hasData checks even with verbose tracing off.
            auto wait_start=Clock::time_point{};
            if(verbose_)wait_start=Clock::now();
            for(auto& t:tensors){
                check(t.hasData(),"SDK operator output has no data");
                if(sync_each_&&!t.waitForReady(std::chrono::seconds(timeout_)))
                    throw HardwareFault("OP_OUTPUT_TIMEOUT op="+std::to_string(id));
            }
            ++post_count;post_ids.push_back(id);
            if(verbose_){
                Json outputs=Json::array();
                for(auto& t:tensors){
                    Json entry={{"offset",t.offset()}};
                    if(t.data().ptype()!=icraft::xrt::PtrType::CPTR)entry["address"]=t.data().addr();
                    else entry["address"]=nullptr;
                    outputs.push_back(entry);
                }
                event("op_post",{{"op_id",id},{"name",op->name},{"outputs",outputs},
                      {"output_wait_ms",ms(wait_start)},{"op_elapsed_ms",ms(op_start_.at(id))}});
            }
        });
    }
    void end(){
        if(verbose_)event("forward_complete",{{"pre_count",pre_count},{"post_count",post_count},
              {"pre_ids",pre_ids},{"post_ids",post_ids},{"elapsed_ms",ms(started_)}});
        if(post_count==0||pre_ids!=post_ids)
            throw HardwareFault("SDK_OPERATOR_CALLBACK_SEQUENCE_INCOMPLETE");
    }
};
}
