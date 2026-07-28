#!/usr/bin/env bash
# Guard the invariants that must hold across every pkg/pocket/Cores/* package.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

fail=0

# bitstream.rbf_r and loader.bin are one shared artifact fanned out. They are
# build products, so absence everywhere is fine (fresh checkout); present in
# only some packages is drift.
for bin in bitstream.rbf_r loader.bin; do
  # `|| true`: with set -e + pipefail, a glob that matches nothing makes ls
  # exit non-zero and aborts the script before the "absent everywhere" guard
  # below can run (the case on a fresh checkout, where binaries aren't built).
  present=$(ls pkg/pocket/Cores/*/"$bin" 2>/dev/null | wc -l || true)
  total=$(ls -d pkg/pocket/Cores/*/ | wc -l)
  if [ "$present" -eq 0 ]; then
    continue
  elif [ "$present" -ne "$total" ]; then
    echo "DRIFT: $bin present in only $present of $total packages"
    fail=1
  elif [ "$(md5sum pkg/pocket/Cores/*/"$bin" | awk '{print $1}' | sort -u | wc -l)" -ne 1 ]; then
    echo "DRIFT: $bin differs across packages:"
    md5sum pkg/pocket/Cores/*/"$bin"
    fail=1
  fi
done

# audio.json, variants.json, info.txt and icon.bin have no intentional divergences
for json in audio.json variants.json info.txt icon.bin; do
  if [ "$(md5sum pkg/pocket/Cores/*/"$json" | awk '{print $1}' | sort -u | wc -l)" -ne 1 ]; then
    echo "DRIFT: $json differs across packages:"
    md5sum pkg/pocket/Cores/*/"$json"
    fail=1
  fi
done

# interact.json: packages sharing one bitstream are expected to have identical
# menus except for genuinely platform-specific entries (an option one system has
# and another does not, or an id reused for a different option). List those ids
# here; after dropping them the rest must be identical.
#   25 FM Sound, 45 BIOS, 55 Legacy Palette: SMS only
#   35 TV System / GG Resolution and 40 Blank Border / Game Gear Link: reused on GG
#   50 Mapper: SMS and SG-1000 only
intentional_ids='[25,35,40,45,50,55]'
interact_hash() {
  jq -S --argjson skip "$intentional_ids" \
    '[.interact.variables[] | select(.id as $i | ($skip | index($i)) == null)]' "$1" \
    | md5sum | awk '{print $1}'
}
if [ "$(for f in pkg/pocket/Cores/*/interact.json; do interact_hash "$f"; done | sort -u | wc -l)" -ne 1 ]; then
  echo "DRIFT: interact.json differs across packages beyond the intentional ids ($(jq -rn --argjson s "$intentional_ids" '$s | map(tostring) | join("/")')):"
  for f in pkg/pocket/Cores/*/interact.json; do
    echo "  $f: $(interact_hash "$f")"
  done
  fail=1
fi

# AnalogueOS resolves core files by Cores/<author>.<shortname>/ at launch,
# so the package folder name must equal author.shortname exactly
for d in pkg/pocket/Cores/*/; do
  name=$(jq -r '.core.metadata.author + "." + .core.metadata.shortname' "$d/core.json")
  if [ "$(basename "$d")" != "$name" ]; then
    echo "DRIFT: folder $(basename "$d") != author.shortname $name"
    fail=1
  fi
done

# The Chip32 VM program is optional, but a core.json naming one must have a
# source to build it from, or the package ships a core.json pointing at a file
# that is not in the zip.
for f in pkg/pocket/Cores/*/core.json; do
  vm=$(jq -r '.core.framework.chip32_vm // empty' "$f")
  if [ -n "$vm" ] && [ ! -f support/loader.asm ]; then
    echo "DRIFT: $f declares chip32_vm '$vm' but support/loader.asm is gone"
    fail=1
  fi
done

# core.json metadata diverges per platform, but version/date must move in lockstep
for field in version date_release; do
  if [ "$(jq -r ".core.metadata.$field" pkg/pocket/Cores/*/core.json | sort -u | wc -l)" -ne 1 ]; then
    echo "DRIFT: core.json $field differs across packages:"
    jq -r ".core.metadata.$field" pkg/pocket/Cores/*/core.json
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "Package consistency check FAILED."
  exit 1
fi
echo "Package consistency check OK."
