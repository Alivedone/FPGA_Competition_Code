#include "ps_hotpath.hpp"
#include <array>
#include <cmath>
#include <cstring>

namespace v3::ps {
std::uint32_t crc32(const unsigned char* data,std::size_t size) noexcept {
    static const auto table=[] {
        std::array<std::uint32_t,256> t{};
        for(std::uint32_t i=0;i<256;++i){auto x=i;for(int k=0;k<8;++k)x=(x>>1)^((x&1)?0xedb88320u:0);t[i]=x;}
        return t;
    }();
    std::uint32_t value=0xffffffffu;
    for(std::size_t i=0;i<size;++i)value=table[(value^data[i])&255]^(value>>8);
    return value^0xffffffffu;
}
bool finite_range(const unsigned char* data,std::size_t size,
                  bool has_lower,double lower,bool has_upper,double upper) noexcept {
    for(std::size_t i=0;i<size/sizeof(float);++i){
        float value;std::memcpy(&value,data+i*sizeof(float),sizeof(value));
        if(!std::isfinite(value)||(has_lower&&value<lower)||(has_upper&&value>upper))return false;
    }
    return true;
}
void secure_zero(unsigned char* data,std::size_t size) noexcept {
    // Keep observable volatile stores: never replace this with an elidable memset.
    volatile unsigned char* dest=data;
    for(std::size_t i=0;i<size;++i)dest[i]=0;
}
}
