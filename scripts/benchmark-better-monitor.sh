#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/dist/Better Monitor.app"
REPORT_PATH="$ROOT_DIR/dist/performance-report.md"
SAMPLES="${SAMPLES:-6}"
INTERVAL="${INTERVAL:-1}"
COMPARE_ACTIVITY_MONITOR="${COMPARE_ACTIVITY_MONITOR:-0}"

now_seconds() {
    /usr/bin/perl -MTime::HiRes=time -e 'printf "%.3f\n", time'
}

elapsed_ms() {
    /usr/bin/perl -e 'printf "%.0f\n", (($ARGV[1] - $ARGV[0]) * 1000)' "$1" "$2"
}

wait_for_process() {
    local pattern="$1"
    local deadline
    deadline="$(/usr/bin/perl -MTime::HiRes=time -e 'printf "%.3f\n", time + 10')"
    local pid=""

    while true; do
        pid="$(pgrep -x "$pattern" | head -1 || true)"
        if [[ -n "$pid" ]]; then
            echo "$pid"
            return 0
        fi

        local current
        current="$(now_seconds)"
        if /usr/bin/perl -e 'exit !($ARGV[0] > $ARGV[1])' "$current" "$deadline"; then
            return 1
        fi
        sleep 0.1
    done
}

sample_process() {
    local pid="$1"
    local name="$2"
    local output="$3"

    : > "$output"
    for _ in $(seq 1 "$SAMPLES"); do
        if ! ps -p "$pid" >/dev/null 2>&1; then
            break
        fi
        ps -p "$pid" -o %cpu=,rss= | awk -v name="$name" '{ printf "%s,%s,%s\n", name, $1, $2 }' >> "$output"
        sleep "$INTERVAL"
    done
}

summarize_samples() {
    local input="$1"
    awk -F, '
        NF == 3 {
            count += 1
            cpu += $2
            rss += $3
            if ($2 > max_cpu) max_cpu = $2
            if ($3 > max_rss) max_rss = $3
        }
        END {
            if (count == 0) {
                printf "0,0,0,0,0"
            } else {
                printf "%d,%.2f,%.2f,%.2f,%.2f", count, cpu / count, max_cpu, rss / count / 1024, max_rss / 1024
            }
        }
    ' "$input"
}

app_was_running=0
activity_was_running=0
better_pid=""
activity_pid=""

mkdir -p "$ROOT_DIR/dist"

if [[ ! -d "$APP_PATH" ]]; then
    "$ROOT_DIR/scripts/package-better-monitor.sh" >/dev/null
fi

if pgrep -x "Better Monitor" >/dev/null 2>&1; then
    app_was_running=1
fi

start="$(now_seconds)"
open -n "$APP_PATH"
better_pid="$(wait_for_process "Better Monitor")"
end="$(now_seconds)"
better_launch_ms="$(elapsed_ms "$start" "$end")"

if [[ "$COMPARE_ACTIVITY_MONITOR" == "1" ]]; then
    if pgrep -x "Activity Monitor" >/dev/null 2>&1; then
        activity_was_running=1
    fi
    activity_start="$(now_seconds)"
    open -a "Activity Monitor"
    activity_pid="$(wait_for_process "Activity Monitor")"
    activity_end="$(now_seconds)"
    activity_launch_ms="$(elapsed_ms "$activity_start" "$activity_end")"
else
    activity_launch_ms="n/a"
fi

better_samples="$(mktemp)"
activity_samples="$(mktemp)"
trap 'rm -f "$better_samples" "$activity_samples"' EXIT

sample_process "$better_pid" "Better Monitor" "$better_samples" &
better_sampler_pid=$!

if [[ -n "$activity_pid" ]]; then
    sample_process "$activity_pid" "Activity Monitor" "$activity_samples" &
    activity_sampler_pid=$!
else
    activity_sampler_pid=""
fi

wait "$better_sampler_pid" || true
if [[ -n "$activity_sampler_pid" ]]; then
    wait "$activity_sampler_pid" || true
fi

IFS=, read -r better_count better_avg_cpu better_max_cpu better_avg_rss better_max_rss <<< "$(summarize_samples "$better_samples")"
if [[ -n "$activity_pid" ]]; then
    IFS=, read -r activity_count activity_avg_cpu activity_max_cpu activity_avg_rss activity_max_rss <<< "$(summarize_samples "$activity_samples")"
else
    activity_count=0
    activity_avg_cpu="n/a"
    activity_max_cpu="n/a"
    activity_avg_rss="n/a"
    activity_max_rss="n/a"
fi

cat > "$REPORT_PATH" <<REPORT
# Better Monitor Performance Report

Generated: $(date)

## Configuration

- Samples: $SAMPLES
- Interval seconds: $INTERVAL
- Compare Activity Monitor: $COMPARE_ACTIVITY_MONITOR
- Better Monitor PID: $better_pid
- Activity Monitor PID: ${activity_pid:-n/a}

## Launch

| App | Launch detection |
| --- | ---: |
| Better Monitor | ${better_launch_ms} ms |
| Activity Monitor | ${activity_launch_ms} ms |

## Runtime Samples

| App | Samples | Avg CPU | Max CPU | Avg RSS | Max RSS |
| --- | ---: | ---: | ---: | ---: | ---: |
| Better Monitor | $better_count | ${better_avg_cpu}% | ${better_max_cpu}% | ${better_avg_rss} MB | ${better_max_rss} MB |
| Activity Monitor | $activity_count | ${activity_avg_cpu}% | ${activity_max_cpu}% | ${activity_avg_rss} MB | ${activity_max_rss} MB |

## Notes

- Launch detection measures time from \`open\` to process discovery, not first painted frame.
- RSS is sampled with \`ps\` and reported in MB.
- CPU is sampled with \`ps\`; short sampling windows can be noisy.
- This is a local comparison helper, not a substitute for Instruments traces.
REPORT

if [[ "$app_was_running" == "0" ]]; then
    osascript -e 'tell application "Better Monitor" to quit' >/dev/null 2>&1 || true
fi

if [[ "$COMPARE_ACTIVITY_MONITOR" == "1" && "$activity_was_running" == "0" ]]; then
    osascript -e 'tell application "Activity Monitor" to quit' >/dev/null 2>&1 || true
fi

echo "$REPORT_PATH"
