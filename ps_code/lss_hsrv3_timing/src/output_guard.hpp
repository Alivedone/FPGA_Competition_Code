#pragma once
#include "core.hpp"
namespace v3 {
inline bool untouched_output(const Bytes& b){
    return !b.empty()&&std::all_of(b.begin(),b.end(),[](unsigned char x){return x==0xff;});
}
inline void verify_hardware_output(const Bytes& tensor,const Bytes& direct_before,const Bytes& direct_after){
    if(tensor!=direct_before||tensor!=direct_after)
        throw HardwareFault("OUTPUT_READBACK_UNSTABLE: Tensor/direct DDR reads differ; preserve buffers and restart board");
    if(untouched_output(tensor))
        throw HardwareFault("OUTPUT_NOT_WRITTEN: SDK returned but output is still all 0xff; preserve buffers and restart board");
    if(tensor.empty()||tensor.size()%4)throw HardwareFault("INVALID_HARDWARE_OUTPUT_SIZE");
    for(size_t i=0;i<tensor.size()/4;++i)if(!std::isfinite(fp(tensor,i)))
        throw HardwareFault("NONFINITE_HARDWARE_OUTPUT: preserve buffers and restart board");
}
}
