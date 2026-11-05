#include "service.hpp"
#include "hardware.hpp"
#include "hmi_uart.hpp"

int main(int argc,char** argv) {using namespace v3;try {
    const uint16_t endian=1;check(*reinterpret_cast<const unsigned char*>(&endian)==1&&sizeof(float)==4,"little-endian FP32 host required");
    std::map<std::string,std::string> args;std::string mode;
    for(int i=1;i<argc;++i) {
        std::string key=argv[i];if(key=="--help") {
            std::cout<<"lss_v3 --serve|--file|--binding-check --config FILE [--backend hardware|reference]\n"
                     <<"  --serve: --bind 0.0.0.0 --port 5001 --feedback serial|tcp --timeout 30\n"
                     <<"  --file: --input BIN --output-dir NEW_DIR --start-frame 0 --windows 1 --stride 1\n"
                     <<"  limits: --max-file-bytes 67108864 --max-windows 4096 --hardware-timeout 120 --audit-model false|true --trace-runtime false|true --sync-each-op true|false\n"
                     <<"  NPU policy: F; --sync-each-op is recorded for compatibility but effective per-op wait is false.\n"
                     <<"  HMI optional: --hmi-device /dev/DEVICE --hmi-history FILE --hmi-dry-run FILE\n"
                     <<"  HMI uses 115200 8N1 GB2312, always-on V3_PERF timing; omitted HMI options keep original behavior.\n";return 0;}
        if(key=="--serve"||key=="--file"||key=="--binding-check"){check(mode.empty(),"choose one mode");mode=key;continue;}
        static const std::set<std::string> allowed={"--config","--backend","--bind","--port","--feedback","--timeout","--max-file-bytes","--max-windows","--hardware-timeout","--input","--output-dir","--start-frame","--windows","--stride","--once","--audit-model","--trace-runtime","--sync-each-op","--hmi-device","--hmi-history","--hmi-dry-run"};
        check(allowed.count(key)&&i+1<argc&&!args.count(key),"unknown/missing/duplicate argument: "+key);args[key]=argv[++i];
    }
    check(!mode.empty()&&args.count("--config"),"mode and --config required; see --help");
    if(mode!="--file")for(auto key:{"--input","--output-dir","--start-frame","--windows","--stride"})check(!args.count(key),std::string("file-mode option in another mode: ")+key);
    if(mode!="--serve")for(auto key:{"--bind","--port","--feedback","--once"})check(!args.count(key),std::string("serve-mode option in another mode: ")+key);
    auto get=[&](const std::string& key,const std::string& fallback){return args.count(key)?args.at(key):fallback;};
    auto decimal=[&](const std::string& key,uint64_t fallback){if(!args.count(key))return fallback;auto s=args[key];check(!s.empty()&&std::all_of(s.begin(),s.end(),[](unsigned char c){return c>='0'&&c<='9';}),"unsigned decimal required: "+key);return static_cast<uint64_t>(std::stoull(s));};
    Limits limits;limits.file_bytes=static_cast<size_t>(decimal("--max-file-bytes",limits.file_bytes));limits.windows=decimal("--max-windows",limits.windows);limits.timeout=static_cast<double>(decimal("--timeout",30));
    check(limits.file_bytes>=FRAME&&limits.file_bytes<=256*1024*1024&&limits.windows>0&&limits.windows<=100000&&limits.timeout>0&&limits.timeout<=3600,"invalid limits");
    auto hw_timeout=decimal("--hardware-timeout",120);check(hw_timeout>0&&hw_timeout<=3600,"invalid hardware timeout");
    auto audit=get("--audit-model","false");check(audit=="false"||audit=="true","invalid --audit-model");
    auto trace=get("--trace-runtime","false"),sync_each=get("--sync-each-op","true");
    check(trace=="true"||trace=="false","invalid --trace-runtime");
    check(sync_each=="true"||sync_each=="false","invalid --sync-each-op");
    Config cfg(std::filesystem::absolute(args.at("--config")));auto kind=get("--backend","hardware");check(kind=="reference"||kind=="hardware","unknown backend");
    std::unique_ptr<hmi::Runtime> display;
    std::unique_ptr<v3::Backend> backend;
    if(mode=="--binding-check") {
#ifdef LSS_WITH_ICRAFT
        Hardware binding(cfg,true);auto h=message("BINDING_CHECK");h["model_info"]=binding.info;h["physical_execution"]=false;std::cout<<h.dump()<<std::endl;return 0;
#else
        throw Error("binding check requires build with Icraft");
#endif
    }
    if(args.count("--hmi-device")||args.count("--hmi-history")||args.count("--hmi-dry-run")) {
        hmi::Options options;options.device=get("--hmi-device","");
        options.history=get("--hmi-history","runtime_evidence/hmi_history.jsonl");options.dry_run=get("--hmi-dry-run","");
        display=std::make_unique<hmi::Runtime>(std::move(options),cfg.id);hmi_sink.store(display.get());
    }
    if(kind=="reference")backend=std::make_unique<Reference>(cfg);
    else {
#ifdef LSS_WITH_ICRAFT
        backend=std::make_unique<Hardware>(cfg,false,hw_timeout,audit=="true",trace=="true",sync_each=="true");
#else
        throw Error("hardware backend unavailable; rebuild with LSS_WITH_ICRAFT=ON (no automatic reference fallback)");
#endif
    }
    Service service(*backend,cfg,limits,get("--feedback","serial")=="tcp");service.hardware_timeout=static_cast<double>(hw_timeout);
    check(get("--feedback","serial")=="tcp"||get("--feedback","serial")=="serial","invalid feedback");
    if(mode=="--serve") {
        auto port=decimal("--port",5001);check(port<=65535,"invalid port");auto once=get("--once","false");check(once=="true"||once=="false","invalid --once");
        service.serve(get("--bind","0.0.0.0"),static_cast<uint16_t>(port),once=="true");
    }else {
        check(args.count("--input")&&args.count("--output-dir"),"file mode requires input/output-dir");
        auto data=read_file(args["--input"],limits.file_bytes);auto h=message("START","file_task");
        h["file_bytes"]=data.size();h["frame_count"]=data.size()/FRAME;h["dtype"]="float32_le";h["bins_per_frame"]=512;
        h["window_size"]=10;h["start_frame"]=decimal("--start-frame",0);h["windows"]=decimal("--windows",1);h["stride"]=decimal("--stride",1);h["crc32"]=crc(data);
        auto task=plan(h,limits);std::filesystem::path dest=args["--output-dir"];check(!std::filesystem::exists(dest)&&std::filesystem::create_directory(dest),"new output directory required; parent must exist");
        std::ofstream events(dest/"events.jsonl"),tsv(dest/"windows.tsv");check(bool(events)&&bool(tsv),"cannot open output logs");
        tsv<<"window_index\tstart_frame\toutput_bytes\tcrc32\tphysical_execution\n";
        auto text_save=[&](const char* name,const Json& j){auto s=j.dump(2);save_file(dest/name,Bytes(s.begin(),s.end()));};text_save("task.json",h);text_save("model_info.json",service.metadata());
        auto emit=[&](const Json& event,const Bytes& result){service.event(event);events<<event.dump()<<std::endl;check(bool(events),"event write failed");
            if(event["type"]=="RESULT") {auto start=number(event,"start_frame");auto stem="w10_s"+std::to_string(start);
                save_file(dest/(stem+".output.bin"),result);save_file(dest/(stem+".input.bin"),Bytes(data.begin()+static_cast<ptrdiff_t>(start*FRAME),data.begin()+static_cast<ptrdiff_t>((start+10)*FRAME)));
                tsv<<event["window_index"]<<'\t'<<start<<'\t'<<result.size()<<'\t'<<event["crc32"].get<std::string>()<<'\t'<<service.backend.info["physical_execution"]<<std::endl;check(bool(tsv),"TSV write failed");}
        };
        auto ok=service.run(task,data,emit,[]{return false;});
        if(service.fault.load()&&backend->info["physical_execution"].get<bool>())for(;;)std::this_thread::sleep_for(std::chrono::seconds(1));
        if(!ok)return 1;
        emit(service.ready(),{});
    }
    return service.fault.load()?2:0;
}catch(const std::exception& e){std::cerr<<"V3_FAIL "<<e.what()<<std::endl;return 1;}}
