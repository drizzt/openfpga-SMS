#!/usr/bin/env bash
# Guard the three-package invariants: shared binaries must be byte-identical,
# JSONs without intentional per-platform divergences identical, and core.json
# version/date in lockstep. (core/data/video/input.json legitimately differ
# per platform and are not diffed here; interact.json is checked modulo its
# intentional per-platform ids below.)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

fail=0

# bitstream.rbf_r and chip32.bin are one shared artifact fanned out.
# They are build products (gitignored), so absence everywhere is fine
# (fresh checkout); present in only some packages is drift.
for bin in bitstream.rbf_r chip32.bin; do
  # `|| true`: with set -e + pipefail, a glob that matches nothing makes ls
  # exit non-zero and aborts the script before the "absent everywhere" guard
  # below can run (the case on a fresh checkout, where binaries aren't built).
  present=$(ls pkg/Cores/*/"$bin" 2>/dev/null | wc -l || true)
  total=$(ls -d pkg/Cores/*/ | wc -l)
  if [ "$present" -eq 0 ]; then
    continue
  elif [ "$present" -ne "$total" ]; then
    echo "DRIFT: $bin present in only $present of $total packages"
    fail=1
  elif [ "$(md5sum pkg/Cores/*/"$bin" | awk '{print $1}' | sort -u | wc -l)" -ne 1 ]; then
    echo "DRIFT: $bin differs across packages:"
    md5sum pkg/Cores/*/"$bin"
    fail=1
  fi
done

# audio.json, variants.json, info.txt and icon.bin have no intentional divergences
for json in audio.json variants.json info.txt icon.bin; do
  if [ "$(md5sum pkg/Cores/*/"$json" | awk '{print $1}' | sort -u | wc -l)" -ne 1 ]; then
    echo "DRIFT: $json differs across packages:"
    md5sum pkg/Cores/*/"$json"
    fail=1
  fi
done

# interact.json: the ONLY intentional divergences are platform-specific
# entries (FM Sound id 25 and TV System id 35 missing on GG; GG Resolution
# and Game Gear Link reuse ids 35/40 on GG where TV System/Blank Border are
# absent; BIOS id 45 SMS-only, GG/SG never run the boot ROM; Mapper id 50
# on SMS/SG-1000 only, GG is Sega-mapper only; Legacy Palette id 55 SMS-only,
# SG-1000 already forces the TMS9918 palette and GG legacy modes are moot).
# After dropping those ids, the remaining entries must be identical;
# anything else is drift.
# Single source for the exempt id set so the filter and the drift message
# below cannot desync.
intentional_ids='[25,30,35,40,45,50,55]'
interact_hash() {
  jq -S --argjson skip "$intentional_ids" \
    '[.interact.variables[] | select(.id as $i | ($skip | index($i)) == null)]' "$1" \
    | md5sum | awk '{print $1}'
}
if [ "$(for f in pkg/Cores/*/interact.json; do interact_hash "$f"; done | sort -u | wc -l)" -ne 1 ]; then
  echo "DRIFT: interact.json differs across packages beyond the intentional ids ($(jq -rn --argjson s "$intentional_ids" '$s | map(tostring) | join("/")')):"
  for f in pkg/Cores/*/interact.json; do
    echo "  $f: $(interact_hash "$f")"
  done
  fail=1
fi

# AnalogueOS resolves core files by Cores/<author>.<shortname>/ at launch,
# so the package folder name must equal author.shortname exactly
for d in pkg/Cores/*/; do
  name=$(jq -r '.core.metadata.author + "." + .core.metadata.shortname' "$d/core.json")
  if [ "$(basename "$d")" != "$name" ]; then
    echo "DRIFT: folder $(basename "$d") != author.shortname $name"
    fail=1
  fi
done

# core.json metadata diverges per platform, but version/date must move in lockstep
for field in version date_release; do
  if [ "$(jq -r ".core.metadata.$field" pkg/Cores/*/core.json | sort -u | wc -l)" -ne 1 ]; then
    echo "DRIFT: core.json $field differs across packages:"
    jq -r ".core.metadata.$field" pkg/Cores/*/core.json
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "Package consistency check FAILED."
  exit 1
fi
echo "Package consistency check OK."
