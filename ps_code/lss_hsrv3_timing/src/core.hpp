#pragma once
#include "../vendor/json.hpp"
#include "ps_hotpath.hpp"
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstring>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <memory>
#include <limits>
#include <map>
#include <mutex>
#include <set>
#include <sstream>
#include <stdexcept>
#include <thread>
#include <vector>

namespace v3 {
using Json=nlohmann::json;
using Bytes=std::vector<unsigned char>;
using Clock=std::chrono::steady_clock;
constexpr size_t FRAME=2048, WINDOW=20480, MAX_HEADER=65536, MAX_OUTPUT=16*1024*1024;
struct Error:std::runtime_error {using std::runtime_error::runtime_error;};
struct HardwareFault:Error {using Error::Error;};
inline void check(bool ok,const std::string& what) {if(!ok)throw Error(what);}
inline uint64_t number(const Json& j,const char* k,uint64_t low=0,uint64_t high=INT64_MAX) {
    check(j.contains(k)&&(j[k].is_number_unsigned()||j[k].is_number_integer()),std::string("integer required: ")+k);
    if(j[k].is_number_integer()&&!j[k].is_number_unsigned())check(j[k].get<int64_t>()>=0,std::string("negative: ")+k);
    auto n=j[k].get<uint64_t>();check(n>=low&&n<=high,std::string("integer out of range: ")+k);return n;
}
inline Json parse(const std::string& text) {
    std::vector<std::set<std::string>> keys;
    return Json::parse(text,[&](int depth,Json::parse_event_t event,Json& node) {
        check(depth<=32,"JSON nesting exceeds limit");
        if(event==Json::parse_event_t::object_start)keys.emplace_back();
        if(event==Json::parse_event_t::key)check(keys.back().insert(node.get<std::string>()).second,"duplicate JSON field");
        if(event==Json::parse_event_t::object_end)keys.pop_back();
        return true;
    });
}
inline Bytes read_file(const std::filesystem::path& p,size_t limit) {
    std::ifstream f(p,std::ios::binary|std::ios::ate);check(bool(f),"cannot open file: "+p.string());
    auto n=f.tellg();check(n>=0&&static_cast<uint64_t>(n)<=limit,"file exceeds limit");f.seekg(0);
    Bytes b(static_cast<size_t>(n));check(b.empty()||bool(f.read(reinterpret_cast<char*>(b.data()),n)),"short file read");return b;
}
inline void save_file(const std::filesystem::path& p,const Bytes& data) {
    check(!std::filesystem::exists(p),"refuse overwrite: "+p.string());
    std::ofstream f(p,std::ios::binary);check(bool(f),"cannot create file");
    f.write(reinterpret_cast<const char*>(data.data()),static_cast<std::streamsize>(data.size()));f.close();check(bool(f),"file write failed");
}
#ifdef LSS_PS_BASELINE
inline void wipe(Bytes& b) {volatile unsigned char* p=b.data();for(size_t i=0;i<b.size();++i)p[i]=0;}
#else
inline void wipe(Bytes& b) {ps::secure_zero(b.data(),b.size());}
#endif
#ifdef LSS_PS_BASELINE
inline uint32_t crc32(const Bytes& b) {
    static const auto table=[] {std::array<uint32_t,256> t{};for(uint32_t i=0;i<256;++i){uint32_t x=i;for(int k=0;k<8;++k)x=(x>>1)^((x&1)?0xedb88320u:0);t[i]=x;}return t;}();
    uint32_t x=0xffffffffu;for(auto c:b)x=table[(x^c)&255]^(x>>8);return x^0xffffffffu;
}
#else
inline uint32_t crc32(const Bytes& b) {return ps::crc32(b.data(),b.size());}
#endif
inline std::string crc(const Bytes& b) {std::ostringstream s;s<<std::hex<<std::setw(8)<<std::setfill('0')<<crc32(b);return s.str();}
inline float fp(const Bytes& b,size_t k) {float x;std::memcpy(&x,b.data()+k*4,4);return x;}
inline Json message(const std::string& type,const std::string& id="") {return {{"version",1},{"type",type},{"task_id",id},{"payload_bytes",0}};}
inline void envelope(const Json& h) {
    check(h.is_object()&&number(h,"version")==1,"unsupported protocol version/header");
    check(h.contains("type")&&h["type"].is_string()&&h.contains("task_id")&&h["task_id"].is_string(),"type/task_id required");
    check(h["task_id"].get<std::string>().size()<=64,"task ID too long");number(h,"payload_bytes");
}
struct Limits {size_t file_bytes=64*1024*1024;uint64_t windows=4096;double timeout=30;};
struct Task {std::string id,checksum;uint64_t bytes,start,stride,count;Json request;};
inline Task plan(const Json& h,const Limits& limits) {
    envelope(h);check(h["type"]=="START"&&number(h,"payload_bytes")==0,"START must have no payload");
    auto id=h["task_id"].get<std::string>();check(!id.empty(),"empty task ID");
    for(unsigned char c:id)check((c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'||c=='-',"invalid task ID");
    auto size=number(h,"file_bytes",FRAME,limits.file_bytes);check(size%FRAME==0,"incomplete float32 frames");
    check(number(h,"frame_count",1)==size/FRAME,"frame_count mismatch");
    check(h.value("dtype",std::string())=="float32_le"&&number(h,"bins_per_frame")==512,"unsupported input format");
    check(number(h,"window_size")==10,"window_size must be 10");
    auto start=number(h,"start_frame"),stride=number(h,"stride",1),requested=number(h,"windows");
    auto frames=size/FRAME;check(start<frames&&frames-start>=10,"no complete window");
    auto available=(frames-start-10)/stride+1;check(requested<=available,"windows exceed source");
    auto count=requested?requested:available;check(count<=limits.windows,"window limit exceeded");
    auto sum=h.at("crc32").get<std::string>();check(sum.size()==8,"invalid CRC string");
    for(auto& c:sum){check((c>='0'&&c<='9')||(c>='a'&&c<='f')||(c>='A'&&c<='F'),"invalid CRC string");if(c>='A'&&c<='F')c=static_cast<char>(c-'A'+'a');}
    return {id,sum,size,start,stride,count,h};
}
struct Config {
    bool has_lower=false,has_upper=false;double lower=0,upper=0;
    Json raw;std::string id,kind,semantics;std::filesystem::path json,weights;
    explicit Config(const std::filesystem::path& p) {
        auto data=read_file(p,MAX_HEADER);raw=parse(std::string(data.begin(),data.end()));
        id=raw.at("model_id").get<std::string>();kind=raw.at("kind").get<std::string>();semantics=raw.at("output_semantics").get<std::string>();
        check(!id.empty()&&id.size()<=128,"invalid model ID");
        check(number(raw,"window_size")==10&&raw.at("input_shape")==Json({1,10,512,1}),"fixed NHWC W10 input required");
        check(raw.at("input_dtype")=="float32_le"&&raw.at("preprocessing")=="none","input must be preprocessed FP32; preprocessing is not implicit");
        auto bounds=raw.at("input_range");check(bounds.is_array()&&bounds.size()==2,"input_range required");
        for(auto& n:bounds)check(n.is_null()||(n.is_number()&&std::isfinite(n.get<double>())),"invalid input bound");
        if(!bounds[0].is_null()&&!bounds[1].is_null())check(bounds[0].get<double>()<=bounds[1].get<double>(),"reversed input range");
        has_lower=!bounds[0].is_null();has_upper=!bounds[1].is_null();
        if(has_lower)lower=bounds[0].get<double>();
        if(has_upper)upper=bounds[1].get<double>();
        check(kind=="diagnostic"||kind=="classification","unknown model kind");
        if(kind=="diagnostic")check(semantics=="diagnostic","diagnostic semantics required");
        else {
            check(semantics=="logits"||semantics=="probabilities","explicit classification semantics required");
            auto labels=raw.at("labels");check(labels.is_array()&&!labels.empty()&&labels.size()<=4096,"class labels required");
            for(auto& s:labels)check(s.is_string()&&s.get<std::string>().size()<=256,"invalid class label");
        }
        json=p.parent_path()/raw.at("json").get<std::string>();weights=p.parent_path()/raw.at("raw").get<std::string>();
    }
#ifdef LSS_PS_BASELINE
    void validate(const Bytes& b)const {
        check(!b.empty()&&b.size()%4==0,"invalid FP32 bytes");auto lo=raw["input_range"][0],hi=raw["input_range"][1];
        for(size_t k=0;k<b.size()/4;++k){auto x=fp(b,k);check(std::isfinite(x)&&(lo.is_null()||x>=lo.get<double>())&&(hi.is_null()||x<=hi.get<double>()),"input outside configured finite range");}
    }
#else
    void validate(const Bytes& b)const {
        check(!b.empty()&&b.size()%4==0,"invalid FP32 bytes");
        if(!ps::finite_range(b.data(),b.size(),has_lower,lower,has_upper,upper))
            throw Error("input outside configured finite range");
    }
#endif
};
struct Prediction {Bytes data,pl_input;};
class Backend {
public:
    Json info;virtual ~Backend()=default;
    virtual Prediction infer(const Bytes& window)=0;
    virtual void clean()=0;
};
class Reference final:public Backend {
public:
    explicit Reference(const Config& cfg) {
        check(cfg.kind=="diagnostic","reference backend does not implement ResNet/classification");
        info={{"backend","reference"},{"physical_execution",false},
              {"input",{{"shape",{1,10,512,1}},{"dtype","float32_le"},{"bytes",WINDOW}}},
              {"output",{{"shape",{1,10,512,1}},{"dtype","float32_le"},{"bytes",WINDOW}}}};
    }
    Prediction infer(const Bytes& b)override {
        Prediction p{Bytes(b.size()),b};for(size_t k=0;k<b.size()/4;++k){float x=.5f*fp(b,k)+1;std::memcpy(p.data.data()+4*k,&x,4);}return p;
    }
    void clean()override {} // Reference has no DMA or device buffers.
};
inline void validate_info(const Json& info,const Config& cfg) {
    check(info.at("input")==Json({{"shape",{1,10,512,1}},{"dtype","float32_le"},{"bytes",WINDOW}}),"backend input mismatch");
    auto out=info.at("output");auto size=number(out,"bytes",4,MAX_OUTPUT);check(out.at("dtype")=="float32_le","only external plain FP32 output supported");
    uint64_t elements=1;check(out.at("shape").is_array()&&!out["shape"].empty(),"invalid output shape");
    for(auto d:out["shape"]){check(d.is_number_integer()&&d.get<int64_t>()>0,"invalid output dimension");auto n=d.get<uint64_t>();check(n<=MAX_OUTPUT/4/elements,"output shape exceeds limit");elements*=n;}
    check(elements*4==size,"padded output requires an explicit unpacking adapter");
    if(cfg.kind=="diagnostic")check(size==WINDOW,"diagnostic output size mismatch");
    else check(elements==cfg.raw.at("labels").size(),"class count/output mismatch");
}
inline Json interpret(const Bytes& b,const Bytes& source,const Config& cfg,const Json& info) {
    check(b.size()==number(info.at("output"),"bytes"),"output length mismatch");std::vector<double> values;
    for(size_t k=0;k<b.size()/4;++k){auto x=fp(b,k);check(std::isfinite(x),"nonfinite model output");values.push_back(x);}
    if(cfg.kind=="diagnostic") {
        check(source.size()==WINDOW&&b.size()==WINDOW,"diagnostic shape mismatch");double error=0;
        for(size_t k=0;k<values.size();++k)error=std::max(error,std::abs(values[k]-(.5*fp(source,k)+1)));
        check(error<=(info.at("physical_execution").get<bool>()?2.5:1e-5),"diagnostic arithmetic mismatch");
        std::vector<double> preview(values.begin(),values.begin()+std::min<size_t>(8,values.size()));
        return {{"kind","diagnostic"},{"preview",preview},{"max_abs_error",error}};
    }
    check(values.size()==cfg.raw.at("labels").size(),"labels/output mismatch");double total=0;
    if(cfg.semantics=="logits") {auto peak=*std::max_element(values.begin(),values.end());for(auto& v:values){v=std::exp(v-peak);total+=v;}for(auto& v:values)v/=total;}
    else {for(auto v:values){check(v>=0&&v<=1,"invalid probability");total+=v;}check(std::abs(total-1)<=.01,"probabilities must sum to one");}
    auto k=static_cast<size_t>(std::max_element(values.begin(),values.end())-values.begin());
    return {{"kind","classification"},{"class_id",k},{"class_name",cfg.raw["labels"][k]},{"score",values[k]}};
}
}
