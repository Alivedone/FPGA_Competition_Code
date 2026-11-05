#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
test "$(uname -m)" = aarch64
sha256sum -c SHA256SUMS
mkdir -p build_ps/compat
for spec in dl:libdl.so.2 dw:libdw.so.1; do
    lib=${spec%%:*}; soname=${spec#*:}
    devlib=$(g++ -print-file-name="lib${lib}.so")
    if [ "$devlib" != "lib${lib}.so" ] && [ -f "$devlib" ]; then
        ln -sfn "$devlib" "build_ps/compat/lib${lib}.so"
    else
        runtime=''
        for dir in /lib/aarch64-linux-gnu /usr/lib/aarch64-linux-gnu; do
            if [ -f "$dir/$soname" ]; then runtime="$dir/$soname"; break; fi
        done
        test -n "$runtime" || { echo "Missing $soname"; exit 1; }
        ln -sfn "$runtime" "build_ps/compat/lib${lib}.so"
    fi
done
# Main/NPU stay at -O0; only the CPU ps_hotpath target uses -O2.
cmake -S . -B build_ps -DLSS_WITH_ICRAFT=ON -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DCMAKE_PREFIX_PATH='/usr;/usr/cmake' \
    -DCMAKE_CXX_FLAGS_RELEASE='-O0 -g0 -DNDEBUG' \
    -DCMAKE_EXE_LINKER_FLAGS="-L$PWD/build_ps/compat"
cmake --build build_ps -j1
python3 tools/check_build_flags.py build_ps/compile_commands.json
ldd build_ps/lss_v3_timing | tee build_ps/ldd.txt
if grep -q 'not found' build_ps/ldd.txt; then exit 1; fi
sha256sum build_ps/lss_v3_timing CMakeLists.txt src/* vendor/json.hpp > PS_BUILD_SHA256SUMS
echo 'PS_UPGRADE_BUILD_PASS board_inference_not_tested'
