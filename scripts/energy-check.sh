#!/bin/bash
# Measures what the running Seawall costs, so it never shows up in Activity Monitor's
# "Using Significant Energy". Run it once with nothing locked and once during a block,
# with the menu closed, and leave the Mac alone while it measures.
#
#   scripts/energy-check.sh          # 60 seconds
#   scripts/energy-check.sh 120
#
# Fails when average CPU is above MAX_CPU (default 0.5%), or idle wakeups above
# MAX_WAKEUPS a second (default 5). A block reading a browser in front costs more:
# try MAX_CPU=2 then.
set -euo pipefail

SECONDS_TO_RUN="${1:-60}"
MAX_CPU="${MAX_CPU:-0.5}"
MAX_WAKEUPS="${MAX_WAKEUPS:-5}"

PID="$(pgrep -x Seawall || true)"
if [[ -z "$PID" ]]; then
    echo "Seawall isn't running." >&2
    exit 1
fi

echo "Measuring Seawall ($PID) for $SECONDS_TO_RUN seconds…"
# top's first sample has no CPU figure yet, so take one more and drop it. IDLEW is a
# running total, so the rate comes from the first and last.
top -l "$((SECONDS_TO_RUN + 1))" -s 1 -pid "$PID" -stats pid,cpu,idlew,power 2>/dev/null \
    | awk -v pid="$PID" -v n="$SECONDS_TO_RUN" -v max_cpu="$MAX_CPU" -v max_wake="$MAX_WAKEUPS" '
        $1 == pid {
            sample++
            gsub(/\+/, "", $3)
            if (sample == 1) { first = $3; next }
            cpu += $2; power += $4; last = $3
        }
        END {
            cpu /= n; power /= n; wake = (last - first) / n
            printf "Average CPU     %.2f%%   (limit %s%%)\n", cpu, max_cpu
            printf "Energy impact   %.2f\n", power
            printf "Idle wakeups    %.1f a second   (limit %s)\n", wake, max_wake
            if (cpu > max_cpu || wake > max_wake) { print "Too much."; exit 1 }
            print "OK."
        }'
