#pragma once
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <sys/socket.h>
#include <sys/select.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <cerrno>
#endif
#include "core.hpp"

namespace v3 {
#ifdef _WIN32
using Socket=SOCKET;constexpr Socket BAD=INVALID_SOCKET;
inline void close_socket(Socket s){closesocket(s);}
inline bool again(){auto n=WSAGetLastError();return n==WSAEWOULDBLOCK||n==WSAEINTR;}
struct Network {Network(){WSADATA d;check(WSAStartup(MAKEWORD(2,2),&d)==0,"WSAStartup failed");}~Network(){WSACleanup();}};
inline void nonblocking(Socket s){u_long one=1;check(ioctlsocket(s,FIONBIO,&one)==0,"nonblocking failed");}
#else
using Socket=int;constexpr Socket BAD=-1;
inline void close_socket(Socket s){close(s);}
inline bool again(){return errno==EAGAIN||errno==EWOULDBLOCK||errno==EINTR;}
struct Network {};
inline void nonblocking(Socket s){auto flags=fcntl(s,F_GETFL,0);check(flags>=0&&fcntl(s,F_SETFL,flags|O_NONBLOCK)>=0,"nonblocking failed");}
#endif
struct Transport:Error {using Error::Error;};
struct Closed:Transport {using Transport::Transport;};
struct TimedOut:Transport {size_t transferred;TimedOut(size_t n):Transport("transport deadline"),transferred(n){}};
inline bool wait_socket(Socket s,bool writing,Clock::time_point until) {
    while(true) {
        auto us=std::chrono::duration_cast<std::chrono::microseconds>(until-Clock::now()).count();if(us<=0)return false;
        timeval tv{static_cast<long>(us/1000000),static_cast<long>(us%1000000)};
        fd_set set;FD_ZERO(&set);FD_SET(s,&set);
        auto n=select(static_cast<int>(s)+1,writing?nullptr:&set,writing?&set:nullptr,nullptr,&tv);
        if(n>0)return true;
        if(n==0)return false;
        if(!again())throw Closed("select failed");
    }
}
inline Clock::time_point deadline(double seconds) {return Clock::now()+std::chrono::milliseconds(static_cast<int64_t>(seconds*1000));}
inline void receive_into(Socket s,unsigned char* data,size_t size,Clock::time_point end) {
    size_t done=0;
    while(done<size){if(!wait_socket(s,false,end))throw TimedOut(done);
        int n=recv(s,reinterpret_cast<char*>(data+done),static_cast<int>(std::min<size_t>(size-done,65536)),0);
        if(n>0)done+=static_cast<size_t>(n);else if(n==0)throw Closed("peer disconnected");else if(!again())throw Closed("recv failed");}
}
inline Bytes receive(Socket s,size_t size,double timeout) {
    Bytes b(size);try{receive_into(s,b.data(),size,deadline(timeout));}catch(...){wipe(b);throw;}return b;
}
inline Json header(Socket s,double timeout) {
    std::array<unsigned char,4> prefix{};auto end=deadline(timeout);receive_into(s,prefix.data(),4,end);
    uint32_t n=(uint32_t(prefix[0])<<24)|(uint32_t(prefix[1])<<16)|(uint32_t(prefix[2])<<8)|prefix[3];
    check(n>0&&n<=MAX_HEADER,"invalid header length");std::string raw(n,'\0');
    // A timeout in header body must never be treated as an idle timeout.
    try{receive_into(s,reinterpret_cast<unsigned char*>(&raw[0]),n,end);}catch(const TimedOut&){throw Closed("partial header timed out");}
    auto j=parse(raw);envelope(j);return j;
}
inline void send_bytes(Socket s,const unsigned char* data,size_t size,Clock::time_point end) {
    size_t done=0;
    while(done<size){if(!wait_socket(s,true,end))throw TimedOut(done);
#ifdef _WIN32
        int flags=0;
#else
        int flags=MSG_NOSIGNAL;
#endif
        int n=send(s,reinterpret_cast<const char*>(data+done),static_cast<int>(std::min<size_t>(size-done,65536)),flags);
        if(n>0)done+=static_cast<size_t>(n);else if(n==0)throw Closed("send closed");else if(!again())throw Closed("send failed");}
}
inline void send_frame(Socket s,const Json& h,const Bytes& data,double timeout) {
    check(number(h,"payload_bytes")==data.size(),"outgoing payload mismatch");auto raw=h.dump();check(!raw.empty()&&raw.size()<=MAX_HEADER,"outgoing header limit");
    auto n=static_cast<uint32_t>(raw.size());std::array<unsigned char,4> prefix{{static_cast<unsigned char>(n>>24),static_cast<unsigned char>(n>>16),static_cast<unsigned char>(n>>8),static_cast<unsigned char>(n)}};
    auto end=deadline(timeout);send_bytes(s,prefix.data(),4,end);send_bytes(s,reinterpret_cast<const unsigned char*>(raw.data()),raw.size(),end);if(!data.empty())send_bytes(s,data.data(),data.size(),end);
}
}
