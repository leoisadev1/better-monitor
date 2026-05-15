#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_PATH="$ROOT_DIR/dist/sampler-probe-report.md"
LOG_PATH="$(mktemp)"
MAX_AVG_MS="${MAX_AVG_MS:-250}"
MAX_RSS_MB="${MAX_RSS_MB:-128}"

mkdir -p "$ROOT_DIR/dist"
trap 'rm -f "$LOG_PATH"' EXIT

start="$(/usr/bin/perl -MTime::HiRes=time -e 'printf "%.3f\n", time')"
if BETTER_MONITOR_PRINT_PROBE=1 swift test --filter performanceProbeProducesUsableTelemetry >"$LOG_PATH" 2>&1; then
    status="pass"
else
    status="fail"
fi
end="$(/usr/bin/perl -MTime::HiRes=time -e 'printf "%.3f\n", time')"
elapsed_ms="$(/usr/bin/perl -e 'printf "%.0f\n", (($ARGV[1] - $ARGV[0]) * 1000)' "$start" "$end")"
probe_line="$(grep 'BETTER_MONITOR_PROBE' "$LOG_PATH" | tail -1 || true)"
avg_ms=""
rss_bytes=""
rss_mb=""

if [[ -n "$probe_line" ]]; then
    avg_ms="$(printf '%s\n' "$probe_line" | sed -n 's/.*avg_ms=\([0-9.]*\).*/\1/p')"
    rss_bytes="$(printf '%s\n' "$probe_line" | sed -n 's/.*rss_bytes=\([0-9]*\).*/\1/p')"
    if [[ -n "$rss_bytes" ]]; then
        rss_mb="$(/usr/bin/perl -e 'printf "%.2f\n", $ARGV[0] / 1048576' "$rss_bytes")"
    fi
fi

if [[ "$status" == "pass" ]]; then
    if [[ -z "$avg_ms" || -z "$rss_mb" ]]; then
        status="fail"
    elif ! /usr/bin/perl -e 'exit !($ARGV[0] <= $ARGV[1])' "$avg_ms" "$MAX_AVG_MS"; then
        status="fail"
    elif ! /usr/bin/perl -e 'exit !($ARGV[0] <= $ARGV[1])' "$rss_mb" "$MAX_RSS_MB"; then
        status="fail"
    fi
fi

{
    echo "# Better Monitor Sampler Probe"
    echo
    echo "Generated: $(date)"
    echo
    echo "## Result"
    echo
    echo "- Status: $status"
    echo "- Wall time: ${elapsed_ms} ms"
    if [[ -n "$probe_line" ]]; then
        echo "- Telemetry: \`$probe_line\`"
    else
        echo "- Telemetry: unavailable"
    fi
    echo "- Average sample budget: <= ${MAX_AVG_MS} ms"
    echo "- Probe RSS budget: <= ${MAX_RSS_MB} MB"
    if [[ -n "$avg_ms" ]]; then
        echo "- Average sample measured: ${avg_ms} ms"
    fi
    if [[ -n "$rss_mb" ]]; then
        echo "- Probe RSS measured: ${rss_mb} MB"
    fi
    echo
    echo "## Notes"
    echo
    echo "- This probe runs the live sampler through the Swift test target."
    echo "- It does not launch Better Monitor or Activity Monitor."
    echo "- Override budgets with \`MAX_AVG_MS=...\` or \`MAX_RSS_MB=...\`."
    echo "- The GUI benchmark remains available at \`scripts/benchmark-better-monitor.sh\`."
} > "$REPORT_PATH"

cat "$REPORT_PATH"

if [[ "$status" != "pass" ]]; then
    echo
    echo "## Probe Log"
    cat "$LOG_PATH"
    exit 1
fi
