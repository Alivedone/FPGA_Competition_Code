#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")" || exit 1
if pgrep -x lss_v3_baseline >/dev/null || pgrep -x lss_v3 >/dev/null || pgrep -x lss_v2_pipeline >/dev/null || pgrep -x lss_v3_timing >/dev/null; then
    echo 'Stop the existing inference service through the GUI first.'
    exit 1
fi
# Default to the final configuration supplied at repository root.
project_root=$(cd ../.. && pwd -P) || exit 1
config=${1:-$project_root/config/resnet18_sjp.json}
test -f "$config" || { echo "Config missing: $config"; exit 1; }
sha256sum -c PS_BUILD_SHA256SUMS || { echo "PS build missing or stale; run bash build_on_board.sh."; exit 2; }
mkdir -p runtime_evidence
evidence=$(mktemp -d runtime_evidence/timing_XXXXXX) || exit 1
echo "TIMING_EVIDENCE=$PWD/$evidence"
./build_ps/lss_v3_timing --serve --backend hardware --config "$config" \
    --bind 0.0.0.0 --port 5001 --feedback tcp \
    --audit-model false --trace-runtime false --sync-each-op false \
    2>&1 | tee "$evidence/console.log"
rc=${PIPESTATUS[0]}
echo "TIMING_SERVICE_EXIT=$rc" | tee "$evidence/exit.txt"
exit "$rc"
