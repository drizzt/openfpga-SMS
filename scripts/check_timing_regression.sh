#!/usr/bin/env bash
# Usage: check_timing_regression.sh [sta.summary] [baseline] [output.txt]
#
# Strict without a baseline file, a ratchet against the recorded numbers with
# one. The verdict is the first line of the output: pr.yml's gate greps for
# "TIMING OK" and fails the PR when it is absent.
set -euo pipefail

STA="${1:-projects/output_files/sms_pocket.sta.summary}"
BASELINE="${2:-timing_baseline.txt}"
OUT="${3:-timing.txt}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# WNS in ns, TNS as a fraction. Sized off measured fitter noise: renaming the
# RTL directory, with not one line of logic changed, moved WNS by 0.145 ns and
# TNS by 1.3%. Anything tighter than this cries wolf on cosmetic commits.
WNS_TOL=0.250
TNS_TOL=0.10

if [ ! -f "$STA" ]; then
  echo "TIMING UNKNOWN: $STA not found" > "$OUT"
  exit 1
fi
# Worst slack and worst TNS across every clock and corner in the summary.
read -r wns tns < <(awk '
  /^Slack/ { sub(/^Slack *: */, ""); s = $0 + 0; if (nw++ == 0 || s < wns) wns = s }
  /^TNS/   { sub(/^TNS *: */, "");   t = $0 + 0; if (nt++ == 0 || t < tns) tns = t }
  END      { if (nw) printf "%.3f %.3f\n", wns, tns; else print "none none" }
' "$STA")

# An empty summary is a broken build, not a passing one.
if [ "$wns" = none ]; then
  echo "TIMING UNKNOWN: no Slack entries in $STA" > "$OUT"
  exit 1
fi

if [ -f "$BASELINE" ]; then
  base_wns=$(awk -F= '/^WNS=/ {print $2}' "$BASELINE")
  base_tns=$(awk -F= '/^TNS=/ {print $2}' "$BASELINE")
  if [ -z "$base_wns" ] || [ -z "$base_tns" ]; then
    echo "TIMING UNKNOWN: $BASELINE has no WNS=/TNS= line" > "$OUT"
    exit 1
  fi
  verdict=$(awk -v w="$wns" -v t="$tns" -v bw="$base_wns" -v bt="$base_tns" \
                -v wtol="$WNS_TOL" -v ttol="$TNS_TOL" '
    BEGIN {
      # TNS is negative, so a worse build is a more negative number.
      if (w < bw - wtol)            print "WNS"
      else if (t < bt * (1 + ttol)) print "TNS"
      else                          print "OK"
    }')
else
  # Strict: no baseline recorded, so nothing may be negative.
  base_wns="n/a"
  base_tns="n/a"
  verdict=$(awk -v w="$wns" 'BEGIN { print (w < 0) ? "STRICT" : "OK" }')
fi

# extract_timing_failures.sh truncates its output file, so it cannot write into
# the block redirection below; give it a temp of its own.
failures=$(mktemp)
trap 'rm -f "$failures"' EXIT
"$SCRIPT_DIR/extract_timing_failures.sh" "$STA" "$failures"

{
  case "$verdict" in
    OK)  echo "TIMING OK" ;;
    WNS) echo "TIMING REGRESSION: worst slack lost more than ${WNS_TOL} ns" ;;
    TNS) echo "TIMING REGRESSION: total negative slack grew more than $(awk -v t="$TNS_TOL" 'BEGIN{printf "%d", t*100}')%" ;;
    STRICT) echo "TIMING NOT MET: negative slack, and no $BASELINE to measure against" ;;
  esac
  echo ""
  printf '%-18s %10s %10s\n' "" "this build" "baseline"
  printf '%-18s %10s %10s\n' "Worst slack (ns)" "$wns" "$base_wns"
  printf '%-18s %10s %10s\n' "Worst TNS (ns)" "$tns" "$base_tns"
  echo ""
  echo "Paths with negative slack:"
  echo ""
  cat "$failures"
} > "$OUT"

[ "$verdict" = OK ]
