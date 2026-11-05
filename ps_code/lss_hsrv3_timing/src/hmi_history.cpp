#include "hmi_history.hpp"
#include <cstdio>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>
#endif

namespace v3::hmi {
std::vector<Request> RequestParser::feed(const unsigned char* data,size_t n) {
    std::vector<Request> out;
    for(size_t i=0;i<n;++i) {
        buffer_.push_back(data[i]);
        while(buffer_.size()>=2&&(buffer_[0]!=0x55||buffer_[1]!=0xaa))buffer_.erase(buffer_.begin());
        if(buffer_.size()<7)continue;
        if(buffer_[4]==255&&buffer_[5]==255&&buffer_[6]==255) {
            auto c=buffer_[2],a=buffer_[3];
            if(((c==1||c==2||c==3||c==0x11||c==0x12)&&a==0)||(c==0x20&&a<5))out.push_back({c,a});
            buffer_.clear();
        }else buffer_.erase(buffer_.begin());
    }
    return out;
}
std::string fixed(double n,int digits) {
    if(!std::isfinite(n)||n<0)return "--";
    std::ostringstream s;s.imbue(std::locale::classic());s<<std::fixed<<std::setprecision(digits)<<n;return s.str();
}
std::string safe_text(const std::string& input,size_t max_chars) {
    std::string out;size_t used=0;
    for(size_t i=0;i<input.size()&&used<max_chars;) {
        unsigned char c=static_cast<unsigned char>(input[i]);size_t n=c<128?1:(c>=0xc2&&c<=0xdf?2:(c>=0xe0&&c<=0xef?3:(c>=0xf0&&c<=0xf4?4:0)));
        bool ok=n&&i+n<=input.size();
        for(size_t j=1;ok&&j<n;++j)ok=(static_cast<unsigned char>(input[i+j])&0xc0)==0x80;
        if(!ok){out+='?';++i;}else if(n==1&&(c<32||c==127||c=='"'||c=='\\')){out+=' ';++i;}else{out.append(input,i,n);i+=n;}
        ++used;
    }
    return out;
}
std::string text_command(const std::string& control,const std::string& text) {
    return control+".txt=\""+safe_text(text)+"\"";
}
History::History(const std::filesystem::path& path):path_(path) {
    if(!path.parent_path().empty())std::filesystem::create_directories(path.parent_path());
    auto lockfile=path;lockfile+=".lock";
#ifdef _WIN32
    auto handle=CreateFileW(lockfile.c_str(),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
    check(handle!=INVALID_HANDLE_VALUE,"HMI history already in use or lock unavailable");
    writer_lock_=std::shared_ptr<void>(handle,[](void* h){CloseHandle(h);});
#else
    int lockfd=::open(lockfile.c_str(),O_CREAT|O_RDWR|O_CLOEXEC,0600);check(lockfd>=0,"cannot open HMI history lock");
    if(flock(lockfd,LOCK_EX|LOCK_NB)!=0){::close(lockfd);throw Error("HMI history already in use");}
    writer_lock_=std::shared_ptr<void>(new int(lockfd),[](void* p){auto f=static_cast<int*>(p);::close(*f);delete f;});
#endif
    bool need_newline=false;size_t bad=0;
    {
        std::ifstream f(path,std::ios::binary);std::string line;
        while(f) {
            auto offset=f.tellg();if(!std::getline(f,line))break;
            need_newline=f.eof();if(line.empty())continue;
            auto j=Json::parse(line,nullptr,false);
            if(j.is_discarded()||!j.is_object()||j.value("schema",0)!=1||!j.contains("id")||!j["id"].is_number_unsigned()) {++bad;continue;}
            auto id=j["id"].get<uint64_t>();
            if(!id||id>1000000000000ULL||!j.contains("summary")||!j["summary"].is_object()){++bad;continue;}
            offsets_[id]=static_cast<std::streamoff>(offset);last_=std::max(last_,id);
        }
    }
    append_.open(path,std::ios::binary|std::ios::app);check(bool(append_),"cannot append HMI history: "+path.string());
    if(need_newline)append_<<'\n';
    if(bad)std::cerr<<"HMI_HISTORY_WARNING skipped_invalid_lines="<<bad<<std::endl;
}
uint64_t History::add(Json record){check(last_<1000000000000ULL,"HMI record ID exhausted");auto id=last_+1;put(id,std::move(record));return id;}
void History::put(uint64_t id,Json record) {
    record["schema"]=1;record["id"]=id;auto offset=append_.tellp();
    append_<<record.dump()<<'\n';append_.flush();check(bool(append_),"HMI history write failed");
    offsets_[id]=static_cast<std::streamoff>(offset);last_=std::max(last_,id);
}
Json History::get(uint64_t id) const {
    auto it=offsets_.find(id);check(it!=offsets_.end(),"unknown HMI history record");
    std::ifstream f(path_,std::ios::binary);check(bool(f),"cannot read HMI history");f.seekg(it->second);std::string line;
    check(bool(std::getline(f,line)),"short HMI history read");auto j=Json::parse(line);
    check(j.value("id",uint64_t(0))==id,"HMI history ID mismatch");return j;
}
size_t History::count(uint64_t anchor) const {return static_cast<size_t>(std::distance(offsets_.begin(),offsets_.upper_bound(anchor)));}
std::vector<uint64_t> History::page(uint64_t anchor,size_t index,size_t size) const {
    std::vector<uint64_t> result;auto it=offsets_.upper_bound(anchor);size_t skip=index*size;
    while(it!=offsets_.begin()&&skip){--it;--skip;}
    while(it!=offsets_.begin()&&result.size()<size){--it;result.push_back(it->first);}return result;
}
Model::Model(History& h,std::string model):history_(h),model_id_(std::move(model)) {
    session_=std::to_string(std::chrono::system_clock::now().time_since_epoch().count());
    latest_=h.last_id();
}
void Model::patch_task(const char* key,const Json& value) {
    for(auto id:task_records_){auto r=history_.get(id);r[key]=value;history_.put(id,std::move(r));}
}
void Model::ingest(const Json& e) {
    const auto type=e.value("type",std::string());
    if(type=="RECEIVED") {
        task_=e.value("task_id",std::string());++generation_;task_records_.clear();pending_window_.clear();window_records_.clear();
        if(!fatal_){state_="处理中";hint_="正在处理新任务";}
        dirty_=page_=="main";return;
    }
    if(type=="RESULT"&&e.contains("summary")&&e["summary"].value("kind",std::string())=="classification") {
        auto index=e.value("window_index",uint64_t(0));
        auto summary=e["summary"];
        check(summary.contains("class_id")&&summary.contains("score")&&std::isfinite(summary["score"].get<double>()),"invalid HMI classification summary");
        Json r={{"session",session_},{"task_generation",generation_},{"task_id",e.value("task_id",std::string())},{"window_index",index},
          {"start_frame",e.value("start_frame",uint64_t(0))},{"model_id",model_id_},{"summary",summary},{"physical_execution",e.value("physical_execution",false)},
          {"received_unix_ms",std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count()}};
        auto it=pending_window_.find(index);if(it!=pending_window_.end()){r["window_perf"]=it->second;pending_window_.erase(it);}
        latest_=history_.add(r);task_records_.push_back(latest_);window_records_.emplace(index,latest_);last_result_=Clock::now();
        hint_=r["physical_execution"].get<bool>()?"最新窗口识别结果":"演示/参考结果，非实板识别";
        if(page_=="main")dirty_=true;else if(page_=="history")history_dirty_=true;
        return;
    }
    if(e.contains("scope")&&e.contains("stages_ms")) {
        if(e.value("task_id",std::string())!=task_)return;
        auto scope=e.value("scope",std::string());
        if(scope=="hardware_window") {
            auto index=e.value("window_index",uint64_t(0));
            auto it=window_records_.find(index);
            if(it==window_records_.end())pending_window_[index]=e;
            else {auto r=history_.get(it->second);r["window_perf"]=e;history_.put(it->second,std::move(r));}
        }else if(scope=="hardware_cleanup")patch_task("cleanup_perf",e);
        else if(scope=="service_task_after_receive")patch_task("task_perf",e);
        if(page_=="main"||(page_=="detail"&&std::find(task_records_.begin(),task_records_.end(),selected_)!=task_records_.end()))dirty_=true;
        return;
    }
    if(type=="READY") {
        if(e.value("scope",std::string())=="service") {
            if(e.contains("model_info"))model_id_=e["model_info"].value("model_id",model_id_);
            if(!fatal_){state_="就绪";hint_=latest_?"任务已清理，等待下一任务":"暂无有效结果，等待开发板数据";}
        }else if(!fatal_)state_="接收中";
    }else if(type=="DONE") {if(!fatal_)state_="清理中";}
    else if(type=="CLEANED") {if(!fatal_)state_="清理完成";}
    else if(type=="STOPPING") {if(!fatal_)state_="正在停止";}
    else if(type=="STOPPED") {if(!fatal_)state_="已停止";}
    else if(type=="ERROR") {
        fatal_=fatal_||e.value("requires_restart",false);state_=fatal_?"硬件故障":"任务失败";
        hint_=(fatal_?"需要重启：":"任务错误：")+e.value("code",std::string("ERROR"));
        if(e.value("task_id",std::string())==task_)patch_task("task_error",e);
    }else return;
    if(page_=="main")dirty_=true;
}
bool Model::request(Request r) {
    if(r.command==1){page_="main";dirty_=true;return true;}
    if(r.command==2){
        if(page_!="detail"){anchor_=history_.last_id();page_index_=0;}
        if(!anchor_)anchor_=history_.last_id();
        page_="history";dirty_=true;return true;
    }
    if(r.command==3){page_="detail";dirty_=true;return true;}
    if((r.command==0x11||r.command==0x12)&&page_=="history") {
        auto count=history_.count(anchor_);auto pages=std::max<size_t>(1,(count+4)/5);
        if(r.command==0x11&&page_index_)--page_index_;
        if(r.command==0x12&&page_index_+1<pages)++page_index_;
        row_ids_.clear();dirty_=true;return true;
    }
    if(r.command==0x20&&page_=="history"&&r.argument<row_ids_.size()) {
        selected_=row_ids_[r.argument];page_="detail";dirty_=true;return true;
    }
    return false;
}
namespace {
std::string rid(uint64_t id){std::ostringstream s;s<<'R'<<std::setw(4)<<std::setfill('0')<<id;return s.str();}
std::string label(const Json& r) {
    auto s=r.at("summary");auto name=s.value("class_name",std::string());
    // Keep the model/TCP labels unchanged; resolve numeric labels only for HMI.
    // Order: dataset/dataset.py label_list, also used by the PC class images.
    const bool numeric=name.empty()||std::all_of(name.begin(),name.end(),[](unsigned char c){return c>='0'&&c<='9';});
    if(!numeric)return safe_text(name,12);
    static const char* const names[]={"UAV1","UAV2","UAV3","UAV4","Bird","Birds","Wing Bird","Rotate","Car"};
    auto id=s.value("class_id",int64_t(-1));
    if(id>=0&&id<9)return names[id];
    return "类别"+std::to_string(id);
}
std::string ms(const Json& record,const char* group,const char* stage=nullptr) {
    if(!record.contains(group))return "--";
    auto j=record[group];if(!j.value("success",false))return "失败";
    if(stage){if(!j.contains("stages_ms")||!j["stages_ms"].contains(stage))return "--";return fixed(j["stages_ms"][stage].get<double>())+" ms";}
    return j.contains("total_ms")?fixed(j["total_ms"].get<double>())+" ms":"--";
}
}
std::vector<std::string> Model::render() {
    std::vector<std::string> out;auto set=[&](const std::string& name,const std::string& value){out.push_back(text_command(page_+"."+name,value));};
    dirty_=false;
    if(page_=="main") {
        set("tState",state_);set("tLink","显示模块运行中");set("tValid",hint_);
        if(!latest_){set("tClass","等待识别");set("tId","--");set("tScore","-- %");set("tWinMs","-- ms");set("tFwdMs","推理调用 -- ms");set("tAge","结果更新：--");return out;}
        auto r=history_.get(latest_);auto s=r["summary"];
        set("tClass",label(r));set("tId",std::to_string(s.value("class_id",uint64_t(0))));set("tScore",fixed(100*s["score"].get<double>(),1)+" %");
        set("tWinMs",ms(r,"window_perf"));set("tFwdMs","推理调用 "+ms(r,"window_perf","forward_ms"));
        auto now=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
        auto age=std::max<int64_t>(0,now-r.value("received_unix_ms",now))/1000;
        set("tAge",age<60?"结果更新："+std::to_string(age)+"秒前":"结果更新："+std::to_string(age/60)+"分钟前");
        const bool current=r.value("session",std::string())==session_&&r.value("task_generation",uint64_t(0))==generation_;
        if(fatal_)set("tValid",hint_);
        else if(!current)set("tValid","上次成功结果；当前尚无新结果");
        else if(!r.value("physical_execution",false))set("tValid","演示/参考结果，非实板识别");
    }else if(page_=="history") {
        auto count=history_.count(anchor_);auto pages=std::max<size_t>(1,(count+4)/5);page_index_=std::min(page_index_,pages-1);
        row_ids_=history_.page(anchor_,page_index_);
        for(size_t i=0;i<5;++i) {
            auto prefix="r"+std::to_string(i);Json r;if(i<row_ids_.size())r=history_.get(row_ids_[i]);
            set(prefix+"Id",r.is_null()?"--":rid(row_ids_[i]));set(prefix+"Class",r.is_null()?"--":label(r));
            set(prefix+"Score",r.is_null()?"--":fixed(100*r["summary"]["score"].get<double>(),1)+" %");set(prefix+"Ms",r.is_null()?"--":ms(r,"window_perf"));
        }
        set("tPage","第"+std::to_string(page_index_+1)+"/"+std::to_string(pages)+"页");
        set("tCount",count?"共"+std::to_string(count)+"条记录，点击查看详情":"暂无历史记录");
        auto notify=notice();out.insert(out.end(),notify.begin(),notify.end());
        for(size_t i=0;i<5;++i)out.push_back("tsw bRow"+std::to_string(i)+","+(i<row_ids_.size()?"1":"0"));
        out.push_back(std::string("tsw bPrev,")+(page_index_?"1":"0"));out.push_back(std::string("tsw bNext,")+(page_index_+1<pages?"1":"0"));
    }else {
        if(!selected_){
            for(auto k:{"tRecord","tTask","tModel","tClass","tScore","tPl","tIn","tFwd","tOut","tWinMs","tTotal","tClean","tStart"})set(k,"--");
            set("tHint","尚未选择有效记录，请返回历史列表");return out;
        }
        auto r=history_.get(selected_);set("tRecord",rid(selected_));set("tTask",safe_text(r.value("task_id",std::string()),18));set("tModel",safe_text(r.value("model_id",std::string()),22));
        set("tClass","识别类别："+label(r));set("tScore","最高预测概率："+fixed(100*r["summary"]["score"].get<double>(),1)+" %");
        set("tPl",ms(r,"window_perf","pl_transfer_ms"));set("tIn",ms(r,"window_perf","input_verify_ms"));set("tFwd",ms(r,"window_perf","forward_ms"));
        std::string read="--";
        if(r.contains("window_perf")&&r["window_perf"].value("success",false)) {
            auto stages=r["window_perf"]["stages_ms"];double sum=0;bool valid=true;
            for(auto k:{"output_read_a_ms","output_read_tensor_ms","output_read_c_ms","output_verify_ms"}) {if(!stages.contains(k))valid=false;else sum+=stages[k].get<double>();}
            if(valid)read=fixed(sum)+" ms";
        }
        set("tOut",read);set("tWinMs",ms(r,"window_perf"));set("tTotal",ms(r,"task_perf"));set("tClean",ms(r,"cleanup_perf"));set("tStart",std::to_string(r.value("start_frame",uint64_t(0))));
        set("tHint",r.contains("task_error")?"本条已产生结果，但所属任务发生错误":(r.value("physical_execution",false)?"历史记录，保持所选数据不自动切换":"演示/参考历史记录，非实板结果"));
    }
    return out;
}
std::vector<std::string> Model::notice() {
    history_dirty_=false;
    if(page_!="history")return {};
    auto n=history_.count()-history_.count(anchor_);
    return {text_command("history.tNew",n?"新增"+std::to_string(n)+"条；返回主页后重进可刷新":"已加载当前历史页")};
}
}
