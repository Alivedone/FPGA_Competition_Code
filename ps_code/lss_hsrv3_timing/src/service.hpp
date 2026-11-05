#pragma once
#include "net.hpp"
#include "perf_summary.hpp"
#include "hmi_bus.hpp"
#include <functional>
#include <iomanip>
#include <locale>
#include <sstream>

namespace v3 {
using Emit=std::function<void(const Json&,const Bytes&)>;
inline int64_t ticks(){return std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now().time_since_epoch()).count();}
class Service {
    std::mutex log_mutex;
    std::mutex operation_mutex;
    std::string operation_task,operation_stage;
    std::atomic<bool> stop_monitor{false};
    std::thread monitor;
public:
    Backend& backend;const Config& cfg;Limits limits;bool tcp_results;
    double hardware_timeout=120;
    std::atomic<bool> stop_requested{false};
    std::atomic<bool> fault{false};std::atomic<int64_t> operation_start{0};
    std::atomic<uint64_t> completed_count{0};
    Service(Backend& b,const Config& c,Limits l,bool tcp):backend(b),cfg(c),limits(l),tcp_results(tcp){
        validate_info(b.info,c);
        if(backend.info["physical_execution"].get<bool>())monitor=std::thread([this]{
            while(!stop_monitor.load()){
                std::this_thread::sleep_for(std::chrono::milliseconds(200));
                std::lock_guard<std::mutex> lock(operation_mutex);
                auto started=operation_start.load();
                if(started&&!fault.load()&&ticks()-started>hardware_timeout*1000){
                    fault=true;
                    event(error(operation_task,operation_stage,"HARDWARE_TIMEOUT","operation stalled; do not kill/reuse; reboot board",completed_count.load(),true));
                }
            }
        });
    }
    ~Service(){stop_monitor=true;if(monitor.joinable())monitor.join();}
    void begin_operation(const std::string& task,const std::string& stage){
        std::lock_guard<std::mutex> lock(operation_mutex);operation_task=task;operation_stage=stage;operation_start=ticks();
    }
    void end_operation(){std::lock_guard<std::mutex> lock(operation_mutex);operation_start=0;}
    void event(Json h) {
        h["physical_execution"]=backend.info["physical_execution"];
        std::lock_guard<std::mutex> lock(log_mutex);std::cout<<h.dump()<<std::endl;
        // Local serial/stdout convenience only; the TCP JSON frame stays unchanged.
        if(h.value("type",std::string())=="RESULT"&&h.contains("summary")&&
           h["summary"].value("kind",std::string())=="classification") {
            const auto& summary=h["summary"];
            std::ostringstream line;line.imbue(std::locale::classic());
            line<<"RESULT class="<<summary.at("class_id").get<size_t>()
                <<" score="<<std::fixed<<std::setprecision(4)<<summary.at("score").get<double>();
            std::cout<<line.str()<<std::endl;
        }
        hmi_publish(h);
    }
    Json metadata()const {
        auto h=backend.info;h["model_id"]=cfg.id;h["model_kind"]=cfg.kind;
        for(auto k:{"preprocessing","input_range","output_semantics","labels"})h[k]=cfg.raw.at(k);
        return h;
    }
    Json ready()const {
        auto h=message("READY");h["scope"]="service";h["model_info"]=metadata();h["max_file_bytes"]=limits.file_bytes;
        h["control"]={{"stop","STOP"},{"policy","finish_task"},{"connection","same"}};
        h["max_windows"]=limits.windows;h["feedback"]=tcp_results?"tcp":"serial";return h;
    }
    Json error(const std::string& id,const std::string& stage,const std::string& code,const std::string& text,uint64_t completed=0,bool restart=false)const {
        auto h=message("ERROR",id);h["stage"]=stage;h["code"]=code;h["message"]=text;
        h["completed_windows"]=completed;h["requires_restart"]=restart;return h;
    }
    bool run(const Task& task,Bytes& data,const Emit& emit,const std::function<bool()>& disconnected) {
        perf_context={task.id,0,task.start};
        PerfSummary task_perf("service_task_after_receive");
        task_perf.set("window_count",task.count);
        task_perf.set("file_bytes",data.size());
#ifdef LSS_PS_BASELINE
        task_perf.set("ps_variant","baseline_instrumented");
#else
        task_perf.set("ps_variant","optimized");
#endif
        for(auto key:{"upload_validation_ms","received_build_send_ms","window_extract_ms","infer_calls_ms",
                      "result_build_send_ms","window_wipe_ms","done_build_send_ms","task_wipe_ms",
                      "cleanup_call_ms","cleaned_event_ms"})task_perf.zero(key);
        std::string validated_crc;
        uint64_t completed=0;completed_count=0;std::string stage="validation";bool ok=false;Bytes window;Prediction prediction;
        auto safe_error=[&](const std::string& code,const std::string& text,bool restart){task_perf.set("error_stage",stage);task_perf.set("error_code",code);try{emit(error(task.id,stage,code,text,completed,restart),{});}catch(const std::exception&) {}};
        try {
            task_perf.run("upload_validation_ms",[&]{
                check(data.size()==task.bytes,"uploaded length/CRC mismatch");
                validated_crc=task_perf.detail("input_crc_ms",[&]{return crc(data);});
                check(validated_crc==task.checksum,"uploaded length/CRC mismatch");
                task_perf.detail("input_numeric_validate_ms",[&]{cfg.validate(data);});
            });
            task_perf.run("received_build_send_ms",[&]{
                auto received=message("RECEIVED",task.id);received["file_bytes"]=data.size();
#ifdef LSS_PS_BASELINE
                received["crc32"]=crc(data);
#else
                received["crc32"]=validated_crc;
#endif
                emit(received,{});
            });
            stage="processing";
            for(uint64_t i=0;i<task.count;++i) {
                check(!disconnected(),"client disconnected; remaining windows abandoned");check(!fault.load(),"service is in FAULT");
                auto start=task.start+i*task.stride;
                perf_context={task.id,i,start};
                task_perf.run("window_extract_ms",[&]{window.assign(data.begin()+static_cast<ptrdiff_t>(start*FRAME),data.begin()+static_cast<ptrdiff_t>((start+10)*FRAME));});
                task_perf.run("infer_calls_ms",[&]{begin_operation(task.id,"inference");prediction=backend.infer(window);end_operation();});
                if(fault.load())throw HardwareFault("hardware deadline exceeded; no cleanup or reuse");
                task_perf.run("result_build_send_ms",[&]{
                auto summary=interpret(prediction.data,window,cfg,backend.info);
                auto result=message("RESULT",task.id);result["payload_bytes"]=prediction.data.size();result["window_index"]=i;
                result["start_frame"]=start;result["window_size"]=10;result["shape"]=backend.info["output"]["shape"];
                result["dtype"]=backend.info["output"]["dtype"];result["crc32"]=crc(prediction.data);result["summary"]=summary;
                result["physical_execution"]=backend.info["physical_execution"];emit(result,prediction.data);++completed;completed_count=completed;
                });
                task_perf.run("window_wipe_ms",[&]{wipe(window);wipe(prediction.data);wipe(prediction.pl_input);});
            }
            stage="reporting";task_perf.run("done_build_send_ms",[&]{auto done=message("DONE",task.id);done["completed_windows"]=completed;done["ready"]=false;emit(done,{});});ok=true;
        }catch(const HardwareFault& e){fault=true;safe_error("HARDWARE_FAULT",e.what(),true);}
        catch(const std::exception& e){safe_error("TASK_FAILED",e.what(),false);}
        task_perf.run("task_wipe_ms",[&]{wipe(window);wipe(prediction.data);wipe(prediction.pl_input);wipe(data);});
        if(!fault.load()) {
            stage="cleaning";
            try {
                task_perf.run("cleanup_call_ms",[&]{begin_operation(task.id,"cleaning");backend.clean();end_operation();});
                if(fault.load())throw HardwareFault("cleanup deadline exceeded");
                task_perf.run("cleaned_event_ms",[&]{auto clean=message("CLEANED",task.id);clean["scope"]="owned_task_buffers";event(clean);});
            }catch(const std::exception& e){fault=true;safe_error("CLEANUP_FAULT",e.what(),true);ok=false;}
        }
        task_perf.set("completed_windows",completed);
        task_perf.finish(ok&&!fault.load());
        return ok&&!fault.load();
    }
    void connection(Socket sock) {
        enum Phase{IDLE,RECEIVING,PROCESSING,FAULT};
        std::mutex state_mutex,send_mutex;std::atomic<bool> disconnected{false};Phase phase=IDLE;
        std::set<std::string> used;std::unique_ptr<Task> approved;std::thread job;
        int64_t upload_start=0;
        auto emit=[&](const Json& h,const Bytes& payload) {
            event(h);if(h["type"]=="RESULT"&&!tcp_results)return;
            std::lock_guard<std::mutex> lock(send_mutex);
            if(disconnected.load())throw Closed("connection closed");
            try{send_frame(sock,h,payload,limits.timeout);}catch(...){disconnected=true;throw;}
        };
        auto safe_emit=[&](const Json& h){try{emit(h,{});}catch(const std::exception&) {}};
        safe_emit(ready());
        try {
            while(!disconnected.load()&&!fault.load()) {
                {std::lock_guard<std::mutex> lock(state_mutex);if(stop_requested.load()&&phase==IDLE)break;}
                if(!wait_socket(sock,false,deadline(.2))) {
                    std::lock_guard<std::mutex> lock(state_mutex);
                    if(phase==RECEIVING&&ticks()-upload_start>limits.timeout*1000)throw Closed("DATA header deadline exceeded");
                    continue;
                }
                Json h=header(sock,limits.timeout);
                std::unique_lock<std::mutex> lock(state_mutex);
                if(h["type"]=="STOP") {
                    if(h["task_id"]!=""||number(h,"payload_bytes")!=0||h.value("scope",Json())!="service"||h.value("policy",Json())!="finish_task") {
                        safe_emit(error("","control","INVALID_STOP","STOP requires empty task_id, zero payload, scope=service, policy=finish_task"));
                        if(number(h,"payload_bytes")!=0)break;
                        continue;
                    }
                    stop_requested=true;
                    auto stopping=message("STOPPING");stopping["scope"]="service";stopping["policy"]="finish_task";
                    stopping["active_task_id"]=phase==PROCESSING?approved->id:"";
                    emit(stopping,{});
                    // RECEIVING here owns only START metadata: DATA has not begun.
                    if(phase==RECEIVING){approved.reset();phase=IDLE;}
                    continue;
                }
                if(stop_requested.load()) {
                    auto busy=message("BUSY",h["task_id"].get<std::string>());busy["stage"]="stopping";emit(busy,{});
                    if(number(h,"payload_bytes")!=0)break;
                    continue;
                }
                if(phase==PROCESSING) {
                    auto busy=message("BUSY",h["task_id"].get<std::string>());busy["stage"]="processing";emit(busy,{});
                    if(number(h,"payload_bytes")!=0)break;
                    continue;
                }
                if(phase==IDLE) {
                    try {
                        auto task=plan(h,limits);check(used.size()<4096&&!used.count(task.id),"duplicate task ID or connection limit; reconnect");
                        used.insert(task.id);approved=std::make_unique<Task>(std::move(task));phase=RECEIVING;upload_start=ticks();
                        auto upload=message("READY",approved->id);upload["scope"]="upload";emit(upload,{});
                    }catch(const Transport&){throw;}
                    catch(const std::exception& e){safe_emit(error(h["task_id"].get<std::string>(),"start","INVALID_START",e.what()));if(number(h,"payload_bytes")!=0)break;safe_emit(ready());}
                    continue;
                }
                if(h["type"]=="START"&&number(h,"payload_bytes")==0){auto busy=message("BUSY",h["task_id"].get<std::string>());busy["stage"]="receiving";emit(busy,{});continue;}
                if(h["type"]!="DATA"||h["task_id"]!=approved->id||number(h,"payload_bytes")!=approved->bytes) {
                    safe_emit(error(approved->id,"receiving","INVALID_DATA","DATA task ID/length mismatch"));break;
                }
                auto task=*approved;lock.unlock();auto data=receive(sock,static_cast<size_t>(task.bytes),limits.timeout);
                if(job.joinable())job.join();
                lock.lock();phase=PROCESSING;
                job=std::thread([&,task,data=std::move(data)]()mutable {
                    run(task,data,emit,[&]{return disconnected.load();});
                    std::lock_guard<std::mutex> guard(state_mutex);
                    if(fault.load()){phase=FAULT;disconnected=true;}
                    else if(!disconnected.load()){
                        // State stays locked until READY is sent: no early task admission.
                        phase=IDLE;approved.reset();if(!stop_requested.load())safe_emit(ready());
                    }
                });
            }
        }catch(const std::exception& e){
            std::lock_guard<std::mutex> lock(state_mutex);
            if(phase!=IDLE||dynamic_cast<const Transport*>(&e)==nullptr)safe_emit(error(approved?approved->id:"","transport","CONNECTION_CLOSED",e.what()));
        }
        disconnected=true;
        // Only the network thread closes its socket, after the task drains safely.
        if(job.joinable())job.join();
        if(stop_requested.load()&&!fault.load()) {
            auto stopped=message("STOPPED");stopped["scope"]="service";stopped["policy"]="finish_task";
            stopped["task_buffers_clean"]=true;
            event(stopped);
            try{send_frame(sock,stopped,{},limits.timeout);}catch(const std::exception&){}
        }
        close_socket(sock);
    }
    void serve(const std::string& bind,uint16_t port,bool once=false) {
        Network network;Socket listener=socket(AF_INET,SOCK_STREAM,0);check(listener!=BAD,"socket failed");
        int one=1;setsockopt(listener,SOL_SOCKET,SO_REUSEADDR,reinterpret_cast<const char*>(&one),sizeof(one));
        sockaddr_in addr{};addr.sin_family=AF_INET;addr.sin_port=htons(port);
        check(inet_pton(AF_INET,bind.c_str(),&addr.sin_addr)==1,"invalid bind IPv4");
        check(::bind(listener,reinterpret_cast<sockaddr*>(&addr),sizeof(addr))==0,"bind failed");check(listen(listener,4)==0,"listen failed");nonblocking(listener);
#ifdef _WIN32
        int len=sizeof(addr);
#else
        socklen_t len=sizeof(addr);
#endif
        check(getsockname(listener,reinterpret_cast<sockaddr*>(&addr),&len)==0,"getsockname failed");
        auto listening=message("LISTENING");listening["bind"]=bind;listening["port"]=ntohs(addr.sin_port);event(listening);
        event(ready()); // Serial-visible wait state before the first PC connection.
        std::thread client;std::atomic<bool> active{false};bool accepted=false;
        while(!fault.load()) {
            if(client.joinable()&&!active.load()){client.join();if(once&&accepted)break;}
            if(stop_requested.load()&&!active.load())break;
            if(!wait_socket(listener,false,deadline(.2)))continue;
            auto sock=accept(listener,nullptr,nullptr);if(sock==BAD){if(again())continue;throw Closed("accept failed");}nonblocking(sock);
            if(active.load()||stop_requested.load()){
                try{auto busy=message("BUSY");busy["stage"]=stop_requested.load()?"stopping":"connection";send_frame(sock,busy,{},limits.timeout);}catch(const std::exception&){}close_socket(sock);continue;
            }
            if(client.joinable())client.join();
            active=true;accepted=true;
            client=std::thread([&,sock]{try{connection(sock);}catch(const std::exception& e){event(error("","connection","INTERNAL",e.what()));close_socket(sock);}active=false;});
        }
        close_socket(listener);
        if(fault.load()&&backend.info["physical_execution"].get<bool>()) {
            event(error("","service","FAULT","no new tasks; reboot board; owner and allocations retained",0,true));
            for(;;)std::this_thread::sleep_for(std::chrono::seconds(1));
        }
        if(client.joinable())client.join();
    }
};
}
