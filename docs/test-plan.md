# On-device test plan — openfpga-SMS

Tied to the port's specific risk areas: the clock change, the scaler slot
announcement, the SDRAM download path, the three-package layout, and the
save writeback — plus general regression against MiSTer behavior.

## 0. Test inventory (prepare first)

- SD card with the release-candidate zip laid out at root (`Cores/`,
  `Platforms/`, `Assets/`).
- ROM set covering every mapper the core claims:
  - **Sega mapper**: Sonic the Hedgehog (SMS), Sonic Triple Trouble (GG)
  - **Codemasters**: Micro Machines or Fantastic Dizzy (SMS) — also
    exercises the 224-line mode
  - **Korean**: Sangokushi 3 or Dodgeball King
  - **MSX/Nemesis**: Nemesis or Penguin Adventure (KR)
  - **Dahjee**: a Taiwanese SG-1000 title (e.g. Rockman/Bomberman Special
    variants)
  - **Linear/no mapper**: any 8–48 KB SG-1000 ROM (Flicky, Girl's Garden)
- **FM title**: Phantasy Star or OutRun (SMS, JP region for FM)
- **Battery save titles**: Phantasy Star (SMS), Shining Force Gaiden (GG)
- **Ys (Japan)** — exercises the cart-ID quirk (forces VDP version 1)
- One **512-byte-headered dump** (size = N×1024+512; verify with `ls -l`)
- **VDPTEST** homebrew ROM (SMSPower) — the CPU clock-enable placement was
  tuned against it
- A 224-line game (Codemasters) and a 240-line case if available; GG games
  for 160×144
- Pocket Dock + a Bluetooth/USB controller (if available)

Each numbered item = pass/fail. Anything failing in §1–§6 blocks 1.0.0.

## 1. Packaging / browsing (three-package invariant)

1. All three platforms appear in the Pocket library: Master System,
   Game Gear, SG-1000, with correct names/years (platform artwork is not
   shipped, see README.md).
2. From each platform, Run → browser opens **its own** Assets folder
   (`sms`, `gg`, `sg1000`) and lists only the matching extension.
3. Load a game from each of the three platforms; correct system mode comes
   up (GG game gets GG palette/viewport, SG-1000 game runs without SMS VDP
   features).
4. Core menu shows the expected version on all three.

## 2. Clock correctness (53.693175 MHz NTSC / 53.203424 MHz PAL)

The PLL was hand-derived and is now runtime-reconfigurable (TV System
toggle rewrites the fractional-K word). Verify NTSC speed exactly with the
toggle on NTSC (the power-up value), then PAL separately:

5. **Pitch test**: record ~30 s of a known music track (e.g. Sonic Green
   Hill) from the headphone jack; compare against MiSTer or a known-good
   emulator recording in a spectrum view. Expect identical pitch; ~0.9%
   flat means the PAL constant got in.
6. **Speed test**: time 60 in-game seconds of a timer (Sonic level timer)
   against a stopwatch — drift should be imperceptible (<0.5 s/min).
7. **VDPTEST ROM**: run it; expect the same pass set as MiSTer SMS (the
   ce_cpu phase was chosen to satisfy it).
8. Smooth 60 Hz scrolling, no periodic stutter or tearing (would indicate
   scaler slot/timing mismatch).
8a. **PAL refresh**: TV System=PAL → frame rate drops to ~49.7 Hz (313-line
    frames). A 50/60 Hz detector homebrew or VDPTEST's display-type
    report should read PAL; a PAL-only title (e.g. "Back to the Future 3",
    California Games PAL scroll speed) runs at correct speed, and
    NTSC-on-PAL shows the classic ~17% slowdown — confirms the VDP really
    runs 313 lines, not just a clock change.
8b. **PAL pitch**: repeat the pitch test under PAL — music should be ~0.9%
    flat vs NTSC (53.203424/53.693175); identical pitch = PLL reconfig
    didn't take. Pitch only proves the clock switch (PSG dividers run off
    clk_sys); a VDP stuck at 262 lines would still pass this — 8a is the
    test that catches line-count failures.
8c. **Toggle robustness**: flip NTSC↔PAL mid-game 5×: PLL relocks within a
    frame, picture returns, SDRAM contents survive (game continues without
    graphics corruption — refresh pauses during relock). Persisted PAL
    setting still applied after power cycle + relaunch.

## 3. Video / scaler slots

9. 192-line game (most SMS titles): image fills correctly, no black
   screen, no mis-scaled window.
10. 224-line game (Codemasters): scaler follows the taller mode; check the
    **transition** title-screen→in-game if the game switches modes — the
    slot announcement must update on the first blanking after DE falls.
11. GG title: 160×144 window centered, correct aspect.
12. GG core display modes: switch between **Original GG** (0x51) and
    **GG+** (0x52) in the Pocket display settings; both render.
13. **GG Resolution toggle** (interact, GG core only): toggle
    standard↔extended full field mid-game; picture reconfigures without
    hang.
14. SMS/SG-1000 cores: confirm the GG Resolution toggle is absent;
    GG core: confirm FM toggle absent.
15. Dock (if available): HDMI output for each of the three line counts
    + GG.

## 4. Download path / SDRAM

16. Load a large ROM (512 KB Phantasy Star), play 10+ min — no graphic
    corruption or crash (SDRAM read-capture multicycle at temperature).
17. **Consecutive loads, shrinking size**: load a 512 KB game, then
    immediately a 32 KB game, then a 256 KB one — each must run correctly
    (cart_mask reset per download; FIFO drain after the downloading flag
    falls).
18. Load the **512-byte-headered dump** — must run identically to the
    headerless version (cart_sz512 last-byte latch).
19. **Ys (Japan)**: title screen and in-game graphics correct (cart-ID
    quirk path).
20. Repeat-load the same game 5× in a row — no degradation (download FSM
    re-arm).

## 5. Saves (battery NVRAM writeback)

21. Phantasy Star: create a save in-game, quit core via menu, relaunch —
    save present.
22. Full **power-off** (not sleep) after quitting core, power on,
    relaunch — save persists on SD (`Saves/sms/...`).
23. GG save title: same cycle on the GG core.
24. Save file is 32768 bytes on the SD card; load it in MiSTer or an
    emulator — cross-compatible.
25. Start a fresh game with **no prior .sav** — core must not boot with
    garbage SRAM (fresh-NVRAM state).
26. Save, then load a **different** game in the same session, then the
    original again — the right save comes back (OS-sequenced load/unload,
    no stale BRAM).

## 6. Inputs

27. SMS: d-pad, B→Button 1, A→Button 2, Start→Pause (pauses e.g. Sonic).
28. SMS: **Select→Reset button** — use a game that polls it (Sonic resets
    to title); confirm GG and SG-1000 cores have **no** Select mapping
    listed in the Pocket controls screen.
29. GG: Start→Start (in-game start menus work).
30. SG-1000: Start→Pause label; buttons 1/2.
31. **Reset Core** interact action on all three — full hardware reset back
    to game boot.
32. Player 2 (dock + second controller): any simultaneous/alternating 2P
    SMS title.

## 7. Audio

33. PSG correct on all three systems (SG-1000 is PSG-only).
34. **FM**: JP region + FM enabled in an FM title — YM2413 music plays;
    toggle **FM Sound off** → falls back to PSG (where the game supports
    it).
35. GG **stereo**: use a game with known hard-panned channels (or the GG
    sound test in Sonic via level select); confirm L/R separation present
    but not absolute (25% crossfeed is intended — channels audible on both
    sides, dominant on one).
36. No pops/clicks at core start, reset, or menu entry; speaker and
    headphone both.

## 8. Settings matrix

37. **Region** US/EU↔Japan: a region-sensitive title changes behavior
    (e.g. translated title screens, or FM availability).
38. **Sprites Per Line** standard↔all: a flicker-heavy scene (R-Type)
    loses flicker with "all".
39. Settings take effect without reload where expected, and survive core
    relaunch per Pocket semantics (document if they reset — interact
    defaults are per-launch unless the persist flag is set).
39a. **TV System** present on SMS and SG-1000 menus, ABSENT on GG (no PAL
     GG shipped); GG always runs NTSC timing regardless of what the other
     packages persisted (interact persistence is per-core-folder).

## 9. Stability / environment

40. 1-hour continuous play session (device warms up — worst case for the
    setup slack at the 85 °C corner the build is signed off at).
41. Pocket **sleep/wake** during gameplay ×3 — resumes or fails gracefully
    (no corrupted state that survives into a new launch).
42. Battery low + charging-while-playing — no SDRAM glitches from rail
    noise (anecdotal Pocket issue; quick check).
43. Menu open/close 10× mid-game — no video/audio desync.

## 10. Release-flow dry run

44. Run the Release action with **patch** first on a throwaway tag to
    validate the CI path end-to-end (loader build step, package
    consistency check, zip layout) before the real **major** run.
45. Unzip the produced release onto a clean SD card and spot-check §1
    again from that artifact — the zip root layout (Assets/Cores/
    Platforms, empty `common/` dirs present, no `.gitkeep`) is what users
    get.

---

Suggested order: §1→§2 first (a clock or scaler fail invalidates
everything else), then §4/§5 (data integrity), then breadth (§3, §6–§8),
stability last.
