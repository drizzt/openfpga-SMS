#!/usr/bin/env bash
# Assemble support/loader.asm into pkg/pocket/Cores/*/loader.bin.
#
# Uses the official bass assembler (ARM9/bass, devel branch) with Analogue's
# chip32 architecture file (open-fpga/bass-chip32). bass expects the
# "architectures" folder next to the executable, so the built binary is
# dropped into the bass-chip32 checkout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ARCH_DIR="$PROJECT_DIR/build_output/bass-chip32"
BASS_SRC="$PROJECT_DIR/build_output/bass-src"
BASS_BIN="$ARCH_DIR/bass"

if [ ! -x "$BASS_BIN" ]; then
    mkdir -p "$PROJECT_DIR/build_output"
    [ -d "$ARCH_DIR" ] || git clone --depth 1 https://github.com/open-fpga/bass-chip32.git "$ARCH_DIR"
    [ -d "$BASS_SRC" ] || git clone --depth 1 -b devel https://github.com/ARM9/bass.git "$BASS_SRC"
    # nall misses <stdexcept> with newer GCC
    grep -q '#include <stdexcept>' "$BASS_SRC/nall/arithmetic/natural.hpp" || \
        sed -i '1a #include <stdexcept>' "$BASS_SRC/nall/arithmetic/natural.hpp"
    make -C "$BASS_SRC/bass" -j"$(nproc)"
    cp "$BASS_SRC/bass/out/bass" "$BASS_BIN"
fi

cd "$PROJECT_DIR/support"
"$BASS_BIN" loader.asm
# the per-platform core packages share one loader
for d in "$PROJECT_DIR"/pkg/pocket/Cores/*/; do
    cp -f loader.bin "$d/loader.bin"
    echo "loader.bin -> ${d#"$PROJECT_DIR/"}loader.bin"
done
rm -f loader.bin
