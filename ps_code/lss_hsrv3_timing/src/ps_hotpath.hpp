#pragma once
#include <cstddef>
#include <cstdint>

namespace v3::ps {
// CPU-only translation unit, compiled independently of the Icraft/NPU wrapper.
std::uint32_t crc32(const unsigned char* data,std::size_t size) noexcept;
bool finite_range(const unsigned char* data,std::size_t size,
                  bool has_lower,double lower,bool has_upper,double upper) noexcept;
void secure_zero(unsigned char* data,std::size_t size) noexcept;
}
