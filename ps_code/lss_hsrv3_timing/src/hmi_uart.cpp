#include "hmi_uart.hpp"
#include <condition_variable>
#include <deque>
#include <cerrno>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <fcntl.h>
#include <iconv.h>
#include <poll.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <termios.h>
#include <unistd.h>
#endif

namespace v3::hmi {
std::string encode_gb2312(const std::string& input) {
#ifdef _WIN32
    if(input.empty())return {};
    auto n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,input.data(),static_cast<int>(input.size()),nullptr,0);
    check(n>0,"HMI invalid UTF-8");std::wstring w(static_cast<size_t>(n),L' ');
    MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,input.data(),static_cast<int>(input.size()),w.data(),n);
    auto m=WideCharToMultiByte(936,0,w.data(),n,nullptr,0,"?",nullptr);check(m>0,"HMI GB2312 conversion failed");
    std::string out(static_cast<size_t>(m),' ');WideCharToMultiByte(936,0,w.data(),n,out.data(),m,"?",nullptr);return out;
#else
    auto cd=iconv_open("GB2312","UTF-8");check(cd!=(iconv_t)-1,"HMI GB2312 iconv unavailable");
    std::string out(input.size()*2+16,'\0');const char* source=input.data();size_t left=input.size();char* dest=out.data();size_t room=out.size();
    while(left) {
        char* in=const_cast<char*>(source);auto rc=iconv(cd,&in,&left,&dest,&room);source=in;
        if(rc!=(size_t)-1)break;
        if(errno==EILSEQ||errno==EINVAL){
            unsigned char c=static_cast<unsigned char>(*source);size_t n=c<0x80?1:(c<0xe0?2:(c<0xf0?3:4));n=std::min(n,left);
            source+=n;left-=n;if(room){*dest++='?';--room;}else{iconv_close(cd);throw Error("HMI conversion overflow");}
        }else{iconv_close(cd);throw Error("HMI GB2312 conversion error");}
    }
    iconv_close(cd);out.resize(static_cast<size_t>(dest-out.data()));return out;
#endif
}
WireEvents WireDecoder::feed(const unsigned char* bytes,size_t n) {
    WireEvents result;
    for(size_t k=0;k<n;++k) {
        buffer_.push_back(bytes[k]);
        while(!buffer_.empty()) {
            if(buffer_[0]==0x55) {
                if(buffer_.size()<2)break;
                if(buffer_[1]==0xaa) {
                    if(buffer_.size()<7)break;
                    if(buffer_[4]==255&&buffer_[5]==255&&buffer_[6]==255) {
                        RequestParser parser;auto r=parser.feed(buffer_.data(),7);result.requests.insert(result.requests.end(),r.begin(),r.end());
                        buffer_.erase(buffer_.begin(),buffer_.begin()+7);continue;
                    }
                }
            }
            if(buffer_.size()<4)break;
            if(buffer_[1]==255&&buffer_[2]==255&&buffer_[3]==255) {
                auto s=buffer_[0];if(s==0x88)result.boot=true;else if(s<=0x24)result.status.push_back(s);
                buffer_.erase(buffer_.begin(),buffer_.begin()+4);
            }else buffer_.erase(buffer_.begin());
        }
    }
    return result;
}

namespace {
struct Serial {
#ifndef _WIN32
    int fd=-1;termios saved{};bool have_saved=false,own_exclusive=false;
#endif
    ~Serial(){close();}
    void close() {
#ifndef _WIN32
        if(fd>=0){if(have_saved)tcsetattr(fd,TCSANOW,&saved);if(own_exclusive)ioctl(fd,TIOCNXCL);::close(fd);}fd=-1;have_saved=false;own_exclusive=false;
#endif
    }
    void open(const std::string& path,unsigned baud) {
#ifdef _WIN32
        (void)path;(void)baud;throw Error("real HMI serial is supported on Linux; use --hmi-dry-run on Windows");
#else
        check(baud==115200,"HMI baud must match current screen: 115200");
        std::error_code ec;auto resolved=std::filesystem::canonical(path,ec);check(!ec,"HMI serial device not found: "+path);
        auto name=resolved.filename().string();
        check(name!="console"&&name!="tty"&&name!="tty0","refuse HMI system terminal");
        std::ifstream active("/sys/class/tty/console/active");std::string console;
        while(active>>console)check(name!=console,"refuse HMI active console: "+name);
        std::ifstream proc("/proc/cmdline");std::string arg;
        while(proc>>arg)if(arg.rfind("console=",0)==0){auto c=arg.substr(8);c=c.substr(0,c.find(','));check(name!=c,"refuse HMI boot console: "+name);}
        fd=::open(resolved.c_str(),O_RDWR|O_NOCTTY|O_NONBLOCK|O_CLOEXEC);check(fd>=0,"cannot open HMI serial: "+path);
        try {
            check(isatty(fd),"HMI device is not a terminal");
            check(flock(fd,LOCK_EX|LOCK_NB)==0,"HMI serial is locked by another process");
            check(ioctl(fd,TIOCEXCL)==0,"cannot exclusively claim HMI serial");
            own_exclusive=true;
            for(int other:{0,1,2})if(isatty(other)) {struct stat a{},b{};if(fstat(fd,&a)==0&&fstat(other,&b)==0)check(a.st_rdev!=b.st_rdev,"refuse HMI process terminal");}
            check(tcgetattr(fd,&saved)==0,"HMI tcgetattr failed");have_saved=true;auto t=saved;cfmakeraw(&t);
            t.c_cflag&=~(PARENB|CSTOPB|CSIZE|CRTSCTS);t.c_cflag|=CS8|CLOCAL|CREAD;
            t.c_iflag&=~(IXON|IXOFF|IXANY);t.c_cc[VMIN]=0;t.c_cc[VTIME]=0;
            check(cfsetispeed(&t,B115200)==0&&cfsetospeed(&t,B115200)==0&&tcsetattr(fd,TCSANOW,&t)==0,"HMI serial setup failed");
            tcflush(fd,TCIOFLUSH);
        }catch(...){close();throw;}
#endif
    }
    bool connected() const {
#ifdef _WIN32
        return false;
#else
        return fd>=0;
#endif
    }
    Bytes read() {
        Bytes out;
#ifndef _WIN32
        unsigned char b[2048];
        pollfd p{fd,POLLIN,0};if(poll(&p,1,0)>0)check(!(p.revents&(POLLERR|POLLHUP|POLLNVAL)),"HMI serial disconnected");
        auto n=::read(fd,b,sizeof(b));if(n>0)out.assign(b,b+n);else if(n<0&&errno!=EAGAIN&&errno!=EWOULDBLOCK&&errno!=EINTR)throw Error("HMI serial read failed");
#endif
        return out;
    }
    size_t write(const std::string& data,size_t offset) {
#ifdef _WIN32
        (void)data;(void)offset;return 0;
#else
        auto n=::write(fd,data.data()+offset,data.size()-offset);
        if(n<0){if(errno==EAGAIN||errno==EWOULDBLOCK||errno==EINTR)return 0;throw Error("HMI serial write failed");}
        return static_cast<size_t>(n);
#endif
    }
};
}

struct Runtime::Impl {
    Options options;History history;Model model;
    std::mutex mutex;std::condition_variable cv;std::deque<Json> events;
    std::atomic<bool> stopping{false},failed{false};std::atomic<uint64_t> dropped{0};
    std::thread thread;Serial serial;WireDecoder decoder;
    std::deque<std::string> commands;std::string active,wire;size_t offset=0;bool waiting=false;
    Clock::time_point started{},next_open=Clock::now(),next_render=Clock::now();
    Clock::time_point next_age=Clock::now();
    std::ofstream dry;
    Impl(Options o,std::string id):options(std::move(o)),history(options.history),model(history,std::move(id)) {
        check(options.baud==115200,"current HMI project requires baud 115200");
        if(!options.dry_run.empty()) {
            if(!options.dry_run.parent_path().empty())std::filesystem::create_directories(options.dry_run.parent_path());
            dry.open(options.dry_run,std::ios::binary|std::ios::app);check(bool(dry),"cannot open HMI dry-run output");
        }
        thread=std::thread([this]{run();});
    }
    ~Impl(){stop();}
    void stop(){stopping=true;cv.notify_all();if(thread.joinable())thread.join();}
    void append(const std::vector<std::string>& batch){for(const auto& s:batch)commands.push_back(s);}
    void disconnect(const std::string& why) {
        std::cerr<<"HMI_LINK_ERROR "<<why<<std::endl;serial.close();decoder=WireDecoder{};commands.clear();active.clear();wire.clear();offset=0;waiting=false;
        next_open=Clock::now()+std::chrono::seconds(2);
    }
    void request(Request r) {
        auto old=model.current_page();
        if(!model.request(r)){
            std::cerr<<"HMI_REQUEST_REJECTED cmd="<<unsigned(r.command)<<" arg="<<unsigned(r.argument)<<std::endl;
            commands.clear();model.refresh();next_render=Clock::now();return;
        }
        commands.clear(); // Already transmitted active command still receives its ACK.
        if(r.command==0x20&&old=="history"&&model.current_page()=="detail")commands.push_back("page detail");
        next_render=Clock::now();
    }
    void run() noexcept {
        try {
            while(true) {
                std::deque<Json> batch;
                {
                    std::unique_lock<std::mutex> lock(mutex);
                    if(events.empty()&&!stopping.load())cv.wait_for(lock,std::chrono::milliseconds(5));
                    for(size_t i=0;i<64&&!events.empty();++i){batch.push_back(std::move(events.front()));events.pop_front();}
                }
                for(const auto& event:batch)model.ingest(event);
                auto losses=dropped.exchange(0);if(losses)std::cerr<<"HMI_QUEUE_OVERFLOW lost_events="<<losses<<" history_may_be_incomplete=true"<<std::endl;
                if(stopping.load()){std::lock_guard<std::mutex> lock(mutex);if(events.empty())break;continue;}
                auto now=Clock::now();
                if(!options.device.empty()&&!serial.connected()&&now>=next_open) {
                    try{serial.open(options.device,options.baud);commands.clear();active.clear();wire.clear();offset=0;waiting=false;decoder=WireDecoder{};
                        commands.push_back("bkcmd=3");commands.push_back("page main");model.request({1,0});std::cerr<<"HMI_CONNECTED device="<<options.device<<std::endl;
                    }catch(const std::exception& e){disconnect(e.what());}
                }
                if(serial.connected()) {
                    try {
                        auto bytes=serial.read();auto rx=decoder.feed(bytes.data(),bytes.size());
                        if(rx.boot){disconnect("screen reboot detected");continue;}
                        for(auto status:rx.status)if(waiting) {
                            if(status!=1)throw Error("screen rejected command code="+std::to_string(status)+" command="+active);
                            active.clear();wire.clear();offset=0;waiting=false;
                        }
                        for(auto r:rx.requests)request(r);
                        if(!active.empty()&&now-started>std::chrono::seconds(2))throw Error("screen command/ACK timeout: "+active);
                    }catch(const std::exception& e){disconnect(e.what());}
                }
                const bool output_ready=serial.connected()||dry.is_open();
                if(output_ready&&model.current_page()=="main"&&now>=next_age){model.request({1,0});next_age=now+std::chrono::seconds(1);}
                if(output_ready&&commands.empty()&&active.empty()&&now>=next_render) {
                    if(model.dirty())append(model.render());
                    else if(model.notice_dirty())append(model.notice());
                    next_render=now+std::chrono::milliseconds(200);
                }
                if(dry.is_open()&&!serial.connected()) {
                    while(!commands.empty()){dry<<commands.front()<<'\n';commands.pop_front();}dry.flush();check(bool(dry),"HMI dry-run write failed");
                }
                if(serial.connected()) {
                    try {
                        if(active.empty()&&!commands.empty()){
                            active=std::move(commands.front());commands.pop_front();wire=encode_gb2312(active)+std::string(3,'\xFF');offset=0;waiting=false;started=now;
                            if(dry.is_open()){dry<<active<<'\n';dry.flush();}
                        }
                        if(!active.empty()&&!waiting){offset+=serial.write(wire,offset);if(offset==wire.size())waiting=true;}
                    }catch(const std::exception& e){disconnect(e.what());}
                }
            }
        }catch(const std::exception& e){failed=true;std::cerr<<"HMI_FATAL "<<e.what()<<" inference_service_not_stopped=true"<<std::endl;}
        serial.close();
    }
};
Runtime::Runtime(Options o,std::string id):impl_(std::make_unique<Impl>(std::move(o),std::move(id))){}
Runtime::~Runtime(){if(hmi_sink.load()==this)hmi_sink.store(nullptr);stop();}
void Runtime::post(const Json& e) noexcept {
    try {
        if(impl_->failed.load()||impl_->stopping.load())return;
        std::lock_guard<std::mutex> lock(impl_->mutex);
        if(impl_->events.size()>=8192){++impl_->dropped;return;}
        impl_->events.push_back(e);impl_->cv.notify_one();
    }catch(...){++impl_->dropped;}
}
bool Runtime::healthy() const noexcept{return !impl_->failed.load();}
void Runtime::stop(){if(impl_)impl_->stop();}
}
