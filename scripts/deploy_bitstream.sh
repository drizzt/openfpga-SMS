#!/usr/bin/env bash
# Reverse the Quartus .rbf for the Pocket and fan it out to every core
# package (the per-platform packages share one bitstream).
# Usage: deploy_bitstream.sh [path/to/ap_core.rbf]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RBF="${1:-$PROJECT_DIR/projects/output_files/ap_core.rbf}"
RBF_R="$PROJECT_DIR/build_output/bitstream.rbf_r"

mkdir -p "$PROJECT_DIR/build_output"
python3 "$SCRIPT_DIR/reverse_bitstream.py" "$RBF" "$RBF_R"
for d in "$PROJECT_DIR"/pkg/Cores/*/; do
  cp -f "$RBF_R" "$d/bitstream.rbf_r"
  echo "bitstream.rbf_r -> ${d#"$PROJECT_DIR/"}bitstream.rbf_r"
done
