# SMS for Analogue Pocket

[![Latest Release](https://img.shields.io/github/v/tag/drizzt/openfpga-SMS?label=latest)](https://github.com/drizzt/openfpga-SMS/releases/latest) [![Downloads](https://img.shields.io/github/downloads/drizzt/openfpga-SMS/total)](https://github.com/drizzt/openfpga-SMS/releases) [![Platform](https://img.shields.io/badge/platform-Analogue%20Pocket-blue)](https://openfpga-library.github.io/analogue-pocket/)

LLM assisted port of [MiSTer SMS core](https://github.com/MiSTer-devel/SMS_MiSTer)

## Features

- **Master System, Game Gear and SG-1000** (NTSC and PAL)
- **Automatic mapper detection** — Sega, Codemasters, Korean, MSX/Nemesis, Dahjee, linear; same logic as MiSTer, with a manual override via the **Mapper** setting
- **PSG + FM audio** — jt89 PSG and YM2413 (VM2413) FM
- **Cart Saves** — 32 KB `.sav`, written back on exit
- **Savestates / Sleep** — Analogue OS savestates and suspend/resume
- **512-byte-headered dumps** handled automatically
- **Game Gear link** — two-wire Gear-to-Gear serial link between two Pockets over the link port (enable per the **Game Gear Link** setting); link cable required
- **Settings** — Region (US/EU / Japan), TV System (NTSC / PAL — SMS and SG-1000, see below), FM Sound, Sprites Per Line, Blank Border (BG color / black — blanks the VDP masked left column, SMS and SG-1000), Game Gear Resolution (standard 160×144 / extended full field), Mapper (override cartridge mapper auto-detection; Auto/Sega/Codemasters/Korean/Linear/Dahjee on SMS, Auto/Linear/Dahjee on SG-1000; auto-reboots the core to apply), Legacy Palette (SMS only: force the TMS9918 color table on the VDPs)

## Currently Not Included

Compared to MiSTer: light gun, paddle, SK-1100
keyboard / SC-3000, System E, Game Genie, multitap,
external/copyrighted Sega BIOS file support.

The internal open boot ROM — Bock's free SMS Boot Loader (SMS Power, 2001) — *is*
included and runs in SMS mode, so BIOS-dependent carts such as Shadow Dancer boot
correctly. It is controlled by the **BIOS** interact setting (Internal by
default; set to Disable to skip the brief SEGA boot splash). The setting can also
be overridden per game by placing a Presets file under
`/Presets/drizzt.SMS/Interact/`. Game Gear and SG-1000 never use a boot ROM.

## Three Cores, One Bitstream

The `drizzt.SMS`, `drizzt.GG` and `drizzt.SG-1000` packages share the same
FPGA bitstream and Chip32 loader, and appear under **Master System**,
**Game Gear** and **SG-1000** in the Pocket library. Each browses only its
own platform folder:

- `Assets/sms/common` — `.sms` ROMs
- `Assets/gg/common` — `.gg` ROMs
- `Assets/sg1000/common` — `.sg` ROMs

Separate packages are required because the Pocket file browser always
opens the Assets folder of the data slot's platform index — it does not
follow the platform the core was launched from. The system mode is
selected automatically from the cartridge file extension by the Chip32
loader (`support/loader.asm`).

## Controls

| Pocket | SMS / GG / SG-1000 |
|---|---|
| D-pad | D-pad |
| B | Button 1 |
| A | Button 2 |
| Start | Pause (SMS/SG) / Start (GG) |
| Select | Reset button (SMS only) |

The SMS Reset button is polled by game software, not a hardware reset
(Game Gear and SG-1000 games never read it, so those cores don't map it).
To hard-reset the core, use "Reset Core" in the Core Settings menu.

## TV System (NTSC / PAL)

The Master System and SG-1000 cores have a **TV System** setting in the
Core Settings menu. PAL switches the whole core to real PAL timing, exactly
like MiSTer: the system clock is reconfigured at runtime from 53.693175 MHz
to 53.203424 MHz and the VDP generates 313-line frames at ~49.7 Hz. Use it
for European releases tuned for 50 Hz — as on real hardware, NTSC games run
~17% slower under PAL (and vice versa). The setting is remembered per core
and applies to every game on that platform; it can also be toggled
mid-game. Game Gear has no such setting — no PAL Game Gear ever existed.

## Installation

1. Download the latest release. Each system ships as its own zip
   (`openfpga-SMS_*.zip`, `openfpga-GG_*.zip`, `openfpga-SG-1000_*.zip`) —
   grab only the platform(s) you want. Each zip contains the `Cores/`,
   `Platforms/` and `Assets/` for that one system. (Installing via Pupdate
   likewise pulls just the platform you pick.)
2. Copy the `Cores/`, `Platforms/`, `Assets/` folders from the zip(s) to the
   root of your SD card
   - **macOS users:** Finder replaces folders instead of merging them, so
     copy the contents manually and be careful.
3. Place your ROMs in `Assets/sms/common`, `Assets/gg/common` and
   `Assets/sg1000/common`

Platform artwork is not bundled. If your SD card doesn't already have
images for these platforms, grab them from
[dyreschlock/pocket-platform-images](https://github.com/dyreschlock/pocket-platform-images)
(or use Pupdate's image-pack option).

## Building from Source

### Prerequisites

- Quartus Prime 21.1 or 25.1 (Standard/Lite) — local install, or Docker/Podman
  with the `raetro/quartus:21.1` image (the CI/release baseline). Both 21.1 and
  25.1 build from the same tree; the project files are kept version-neutral.

### Build

```bash
./scripts/build.sh          # bitstream → pkg/pocket/Cores/*/bitstream.rbf_r
./scripts/build_loader.sh   # loader.bin → pkg/pocket/Cores/*/loader.bin
```

`build.sh` defaults to Quartus 21.1 (matching the CI/release toolchain). To
build with 25.1 instead, point `QUARTUS_DIR` at it:

```bash
./scripts/build.sh                                               # default: 21.1
QUARTUS_DIR=/opt/intelFPGA_lite/25.1/quartus ./scripts/build.sh  # 25.1
```

## Repository Layout

The tree follows the OpenGateware "gateman" layout used by other MiSTer ports
(for example [agg23/openfpga-NES](https://github.com/agg23/openfpga-NES)):

- `rtl/upstream/` : the MiSTer `SMS_MiSTer` core, vendored through the
  `vendor/upstream` branch (see Upstream Sync below).
- `rtl/sms.qip` : selects the subset of `rtl/upstream/` that is compiled.
- `platform/pocket/` : Analogue Pocket APF framework. `pocket.tcl` carries the
  device, pin-out and I/O assignments, which are fixed by the hardware.
- `target/pocket/` : the Pocket integration (top level, clocking, video, audio,
  data loaders), listed in `target/pocket/core.qip`.
- `support/` : `loader.asm`, the Chip32 loader run by the Pocket OS.
- `projects/` : the Quartus project, `sms_pocket.qpf` + `sms_pocket.qsf`. The
  `.qsf` holds only per-core tuning; it sources `pocket.tcl` for the platform and
  pulls sources in through the `.qip` files. Adding a file to the project means
  editing a `.qip`, never the Quartus IDE, which rewrites the `.qsf` and drops
  the `source` line.
- `pkg/pocket/` : the packaged openFPGA cores/assets/platforms.

## Upstream Sync

`.github/copy.bara.sky` mirrors the upstream MiSTer `rtl/` tree onto the
`vendor/upstream` branch, as `rtl/upstream/` and with nothing of this port's
applied. `.github/workflows/upstream.yml` runs it daily, opens one pull request
merging that branch into `master`, and arms auto-merge on it; merging cuts a
release. The cycle is unattended end to end, and stops for a human on a merge
conflict or a red timing gate, on nothing else.

Local changes to vendored files are just commits on `master`. The sync merge
carries them: git's three-way merge sees pristine upstream on both the merge base
and the vendor branch, this port's edits on its side, and reapplies them. There is
no patch set to keep in step with the tree, and a conflict is resolved once, in
the PR, after which the recorded merge keeps it resolved.

To see everything this port changed on top of upstream:

```sh
git diff origin/vendor/upstream master -- rtl/upstream
```

The sync is release-gated: MiSTer commits a compiled `.rbf` under `releases/`
when it cuts a release, so the workflow targets the newest upstream commit that
touches `releases/` and syncs `rtl/` up to that point. Unreleased work-in-progress
commits that only touch `rtl/` are left alone until they are part of a release.
The path comes from `.upstream.release_path` in `gateware.json`.

The PR is built and timing-gated by `.github/workflows/pr.yml`, and merging it
triggers `.github/workflows/release.yml`: version bump, compile, tag, GitHub
release and the three per-platform zips. The bump is a **patch** by default; add
a `release:minor` or `release:major` label to the PR **before** the gate finishes
to override.

The sync needs one repository secret, `CUSTOM_GH_TOKEN`: a fine-grained Personal
Access Token scoped to this repo with **Contents: Read and write** and **Pull
requests: Read and write**. Copybara pushes the vendor branch with it so the
`pull_request` build and the merge-triggered release fire (a branch pushed with
the default `GITHUB_TOKEN` would not trigger them).

### Repository settings the sync depends on

Set these once, or the sync cannot run unattended. `upstream.yml` arms auto-merge
with `--merge`, so the repo has to allow it and has to have something to wait on:

```sh
gh api -X PATCH repos/drizzt/openfpga-SMS \
  -F allow_auto_merge=true -F allow_merge_commit=true \
  -F allow_squash_merge=false -F allow_rebase_merge=false \
  -F delete_branch_on_merge=false

gh api -X PUT repos/drizzt/openfpga-SMS/branches/master/protection \
  -F required_status_checks[strict]=false \
  -f 'required_status_checks[contexts][]=gate' \
  -F enforce_admins=false -F required_pull_request_reviews=null \
  -F restrictions=null
```

Squash or rebase drops the merge parent, so the next sync finds only the seed as
a merge base and replays the whole upstream history against a tree that already
has it. Deleting `vendor/upstream` after merging does the same damage, since
Copybara then has no baseline to fetch, and with nobody watching both fail
silently. Without a required check, auto-merge has nothing to wait for and lands
the PR before the build has said anything.

### Seeding the vendor branch

`rtl/upstream/` was vendored by hand before this model existed, so the branch is
seeded from pristine upstream and joined with `-s ours`, which records the
ancestry without touching the tree. The `GitOrigin-RevId` trailer is Copybara's
baseline, so writing it into the seed commit means no run ever needs the
`last_rev` input.

```sh
git clone https://github.com/MiSTer-devel/SMS_MiSTer.git /tmp/upstream
git -C /tmp/upstream rev-parse HEAD          # the sha for the trailer below

git switch --orphan vendor/upstream
mkdir -p rtl/upstream && cp -r /tmp/upstream/rtl/. rtl/upstream/
git add rtl/upstream
git commit -m "seed vendor branch

GitOrigin-RevId: <upstream sha>"

git switch master
git merge -s ours --allow-unrelated-histories vendor/upstream \
  -m "record vendor/upstream as the merge base for rtl/upstream"
git push origin vendor/upstream master
```

Check it with the `git diff` above before pushing: it must show exactly this
port's intended local changes and nothing else, because that diff is what every
future sync will preserve.

## Credits

- **[SMS_MiSTer](https://github.com/MiSTer-devel/SMS_MiSTer)** — original
  MiSTer core, by its contributors; originally based on Ben's Papilio
  Master System core
- **T80 Z80 core** — Daniel Wallner (BSD-style license, see sources)
- **jt89 PSG** — Jose Tejada (GPLv3)
- **VM2413 OPLL** — Mitsutaka Okazaki
- **APF framework** — Analogue (see file headers)
- **[agg23/analogue-pocket-utils](https://github.com/agg23/analogue-pocket-utils)** —
  data loader/unloader and audio I2S modules (MIT)
- **[mincer-ray/openfpga-GBA](https://github.com/mincer-ray/openfpga-GBA)** —
  reference port this repository is modeled on

## License

This repository as a whole is licensed under the GPLv3 (see LICENSE);
individual files keep their original licenses as noted in their headers.

Note: the VM2413 license forbids selling the object code or using it in a
commercial product; this core is free software and must stay that way.

Bugs in this port are likely port-specific — please do not report them to
the MiSTer SMS repository.
