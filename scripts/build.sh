#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default to Quartus 21.1. 25.1 also builds this tree (project files are kept
# version-neutral, see generate.tcl): opt in with e.g.
# QUARTUS_DIR=/opt/intelFPGA_lite/25.1/quartus.
LOCAL_QUARTUS="${QUARTUS_DIR:-/opt/intelFPGA_lite/21.1/quartus}"

# The toolchain pin, used here and by CI, so there is one image to bump.
QUARTUS_IMAGE="${QUARTUS_IMAGE:-docker.io/raetro/quartus:21.1}"

# The reconfig FSM's NTSC K word (core_top.sv) must equal the PLL's power-up
# fractional division (mf_pllbase_0002.v). Drift is a silent hardware-only
# symptom: power-up frequency differs from the PAL->NTSC reconfig-restored one.
ntsc_k_fsm=$(grep -oP "NTSC_FRAC_K = 32'd\K[0-9]+" "$PROJECT_DIR/target/pocket/core_top.sv")
ntsc_k_pll=$(grep -oP 'pll_fractional_division\("\K[0-9]+' "$PROJECT_DIR/target/pocket/mf_pllbase/mf_pllbase_0002.v")
if [ "$ntsc_k_fsm" != "$ntsc_k_pll" ]; then
  echo "ERROR: NTSC fractional-K mismatch:" >&2
  echo "  core_top.sv NTSC_FRAC_K           = $ntsc_k_fsm" >&2
  echo "  mf_pllbase_0002.v power-up K word = $ntsc_k_pll" >&2
  exit 1
fi

if [ -x "$LOCAL_QUARTUS/bin/quartus_sh" ]; then
  echo "=== Starting Quartus build (local: $LOCAL_QUARTUS) ==="
  cd "$PROJECT_DIR"
  PATH="$LOCAL_QUARTUS/bin:$PATH" quartus_sh -t generate.tcl
else
  echo "=== Starting Quartus build via container ==="
  "${CONTAINER_RUNTIME:-docker}" run --rm \
    -v "$PROJECT_DIR":/build:Z \
    -w /build \
    "$QUARTUS_IMAGE" \
    quartus_sh -t generate.tcl
fi

echo ""
echo "=== Build complete, reversing bitstream ==="
"$SCRIPT_DIR/deploy_bitstream.sh"

echo ""
"$SCRIPT_DIR/print_timing.sh" \
  "$PROJECT_DIR/projects/output_files/sms_pocket.sta.summary" \
  "$PROJECT_DIR/build_output/reports/sms_pocket.sta.clock_summary.rpt"

echo "=== Done! ==="
echo "Bitstream copied to: pkg/pocket/Cores/*/bitstream.rbf_r"
