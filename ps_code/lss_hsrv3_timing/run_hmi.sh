#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")" || exit 1
if [ "$#" -lt 1 ]; then
    echo 'Usage: bash run_hmi.sh /dev/ACTUAL_DEVICE [existing_model_config.json]'
    echo 'No device name is guessed. Stop the old inference service normally first.'
    exit 2
fi
binary_name=${PS_BINARY:-lss_v3_timing}
case "$binary_name" in lss_v3_timing) ;; *) echo "Invalid PS_BINARY"; exit 2 ;; esac
device=$1
project_root=$(cd ../.. && pwd -P) || exit 1
config=${2:-$project_root/config/resnet18_sjp.json}
test -c "$device" || { echo "Not a serial character device: $device"; exit 2; }
test -f "$config" || { echo "Config missing: $config"; exit 2; }
for process in lss_v3_baseline lss_v3 lss_v2_pipeline lss_v3_timing hmi_uart_demo; do
    if pgrep -x "$process" >/dev/null; then
        echo "Stop the existing process normally first: $process"
        exit 2
    fi
done
test -x build_ps/"$binary_name" || { echo 'Run bash build_on_board.sh first.'; exit 2; }
sha256sum -c PS_BUILD_SHA256SUMS || { echo "PS build missing or stale; run bash build_on_board.sh."; exit 2; }
mkdir -p runtime_evidence
evidence=$(mktemp -d runtime_evidence/timing_uart_${binary_name}_XXXXXX) || exit 1
echo "TIMING_EVIDENCE=$PWD/$evidence"
echo "HMI_HISTORY=$PWD/runtime_evidence/hmi_history.jsonl"
./build_ps/"$binary_name" --serve --backend hardware --config "$config" \
    --bind 0.0.0.0 --port 5001 --feedback tcp \
    --audit-model false --trace-runtime false --sync-each-op false \
    --hmi-device "$device" --hmi-history "$PWD/runtime_evidence/hmi_history.jsonl" \
    2>&1 | tee "$evidence/console.log"
rc=${PIPESTATUS[0]}
echo "TIMING_SERVICE_EXIT=$rc" | tee "$evidence/exit.txt"
exit "$rc"
