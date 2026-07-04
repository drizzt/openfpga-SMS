#!/usr/bin/env bash
# Extract failing entries (negative slack) from a Quartus .sta.summary.
# Usage: extract_timing_failures.sh [sta.summary] [output.txt]
set -euo pipefail

STA="${1:-projects/output_files/ap_core.sta.summary}"
OUT="${2:-timing.txt}"

: > "$OUT"
if [ -f "$STA" ]; then
  awk '
    /^Type/  { type_line = $0 }
    /^Slack/ { slack_line = $0; sub(/^Slack *: */, "", slack_line); slack = slack_line + 0 }
    /^TNS/   {
      tns_line = $0; sub(/^TNS *: */, "", tns_line); tns = tns_line + 0
      if (slack < 0) {
        print type_line
        print "Slack: " slack_line
        print "TNS:   " tns_line
        print ""
      }
      type_line = ""; slack = 0
    }
  ' "$STA" > "$OUT"
fi
if [ ! -s "$OUT" ]; then
  echo "No timing closure failures." > "$OUT"
fi
