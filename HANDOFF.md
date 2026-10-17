# Handoff — Aurora FM2K→Godot fidelity fixes (v0.9.x iteration)

Continue-context for the Android debug-APK fidelity work. Branch `main`, repo
`tencentfurrys/aurora-fm2k-godot`. Written 2026‑10‑17 after the black-key /
sprite-scale / stage-layer round.

## Goal
Make the ported APK match the original FM2K Aurora PC look, guided by the two
recordings in the user's Downloads folder (reference gameplay of the stock
build vs a recording of the shipped v0.9 APK).

## What changed in this commit
1. **`godot/scripts/data.gd` — palette-0 black keying on BOTH load paths.**
   Every shipped `data/assets/**` PNG is an RGB8 dump with opaque black
   backing; FM2K treats palette index 0 as transparent. `Data.tex()` now
   converts to RGBA8 and keys pure black to alpha 0 in the dev path
   (`Image.load_from_file`) *and* the exported path
   (`CompressedTexture2D.get_image()` → decompress → key → rebuild).
   Probe helper: `godot/tools/probe_img.gd`.
2. **`godot/scripts/fighter.gd` — fighter art at FM2K proportion.**
   `_spr.scale = 0.5` and `_spr.position = ((±fr.x), fr.y − GROUND_TO_ANCHOR) × 0.5`
   in `_update_sprite()`. Fighters were previously drawn 1:1 in the 320×240
   bridge canvas (~2× oversized). Reference video confirms authentic fighters
   occupy ~40–50 % of frame height; e.g. Luna 242 px → 121 units = 50 %.
3. **`godot/scripts/main.gd` — stage rebuilt as FM2K layer stack + camera.**
   The old `_build_stage` drew only `images[0]` scaled to fit — which rendered
   Discord's Ponyville as just its sky slab and Training Stage as a squashed
   wall. New system:
   - every *named* skill contributes layer strips, drawn bottom-up in skill
     order (`z_index` from −100; placeholders `------None------`,
     `Player Layers`, unnamed, skipped);
   - mapping constants `STAGE_SCALE = 0.5`, `STAGE_Y0 = −146.0` — stage-px
     → bridge units, y anchored so the bank's ground line lands exactly on
     the fighters' `GROUND_Y` (200): `world = (x·0.5, y·0.5 − 146)`;
   - per-layer **parallax** from the parsed FM2K skill settings
     (`width`/`height`, 0–100): `world_x += pan × (1 − w/100)` — 0 = glued to
     the view (sky), ~100 = glued to the world (floor). Weights come from
     `godot/data/stage_parallax.json` (lookup: stage slug → skill name);
   - ambient `moves` drift (mx/my) per layer wraps on the layer's extent and
     is applied ~per-second (÷60 heuristic — unverified vs engine);
   - `Camera2D` follows the fighters' midpoint, clamped to the composed layer
     bounds (`limit_left/right` from strip extents, y locked 0–240).
4. **`godot/export_presets.cfg`** — debug keystore lines
   (`D:/tools/aurora-keys/debug.keystore`, user `androiddebugkey`). Required
   by this machine to export; keep intact through any git operation.
5. **Tooling** — `godot/tools/capture.gd/tscn` (env-driven stamped PC
   captures: `CAPTURE_SCENE`, `CAPTURE_STAMPS`, plus `CAPTURE_STAGE` which
   pokes the static `stage_name/p1_name/p2_name` on `res://scripts/main.gd`),
   `godot/tools/probe_img.gd`, `tools/gen_stage_parallax.py` (regenerates the
   sidecar from the `aurora_fm2k/*.json` parser dumps).
6. **`godot/data/stage_parallax.json`** — `{stage_slug: {skill_name: [w, h]}}`
   (+ harmless character-skill pollution, 188 KB).

## ⚠ Known open bug — top priority on resume
The most recent PC captures (`D:\tools\pc-capture\main-t16.png` = Training
Stage @16 s, `main-t10/t18` = Discord's Ponyville) show **stage art ~3× over-
magnified** (single wall tiles / one playing card fill the view; fighters not
visible in t16) — worse than the immediately-previous verified run
(`pc-cap7/8` logs, since-overwritten `main-t10/t14`). Root cause **not
diagnosed**. Bisect plan, one variable at a time, re-capturing each time:

1. temporarily disable the per-frame `_stage_layers` reposition loop in
   `_process` (layers render at their static base positions);
2. if still wrong, remove the `Camera2D` (fixed 160,120 view);
3. if still wrong, suspect the sprite-`scale = 0.5` interactions
   (double-application) or the capture harness itself.

Capture notes: run with the console exe
`D:\tools\godot\Godot_v4.3-stable_win64_console.exe --path godot
--rendering-driver opengl3 res://tools/capture.tscn` (opengl3 required —
ANGLE falls back otherwise); `--quit-after` counts *frames*, use ≥1600 to
reach 20 s stamps; kill stray `Godot*` processes between retries.

## Ground truth / reference material (all local, not in git)
- `D:\tools\ref-video` — reference frames of the stock FM2K build (854×500).
- `D:\tools\ref-dense` — dense frames around t≈241 s: **Golden Oak Library**
  fight (`f024/f030/f038`) — best look at authentic HUD (framed plate,
  portrait medallions, rainbow gauge, hexagonal timer) and visible per-layer
  parallax while the camera pans.
- `D:\tools\user-video` — user's recording of the shipped v0.9 APK.
- `C:\Users\RDP\Downloads\fim-gameplay.mp4` (reference) and
  `2026_10_17_19_22_15.mp4` (APK).

## Defects still to fix (from the user's APK recording)
- **Select screen**: overlapping roster labels ("Rainbow DasFluttershy",
  "Big MaciGilda"), broken hex masks (black rectangles behind portrait
  hexes), giant green Ponyville stage preview covering the hex grid,
  "SELECT STAGE" text over the logo. Also: the authentic layout is a big left
  character banner + small hexagon portrait column — not the port's grid.
- **Fidelity gap on the in-fight HUD** vs reference (medallion plate, gauge
  art — `main.gd` has `_add_life_art` hooks for KGT 130/131; verify they
  actually render, else port them).
- Gameplay math mixes 320-canvas positions with 640-space sprite/box units
  (pre-existing v0.9 quirk; visuals now agree at ×0.5 but box-vs-sprite
  fidelity is `tools/box_convention.py` territory).

## Engine-truth research lead (paused mid-way)
Parallax weights (skill `Settings.width/height`) were recovered from the FM2K
parser dumps — but the exact *draw-time* semantics (camera anchor, `moves`
timing, wrap) are still inferred. Rejected for now (won't run on this VM):
stock `FightingIsMagic.exe` hangs. Cloned `Armonte/wanwan` (FM2K rollback
suite, `D:\tools\wanwan`) — it reimplements combat *state*, not the stage
draw path. Next leads if the visual bugs resist bisection: fm2k-again style
reimplementations, FM2K_Rollback docs, CncDDraw-era display hooks, FIM
community engine notes.

## Android rebuild + upload (only once captures look right)
Re-export the debug APK exactly as for v0.9.0 (keystore lines above, absolute
output path `godot/export/aurora-v0.9.0-debug.apk`), verify with
`aapt` / `apksigner` / archive listing, then:

```pwsh
$env:GH_TOKEN = "<token>"
gh release upload v0.9.0 godot/export/aurora-v0.9.0-debug.apk --clobber
```

## Environment gotchas
- Working clone (this checkout) lives somewhere temp; **never** `git clean -fd`
  — untracked `godot/android`, `godot/export`, `.godot` caches are load-bearing.
- `aurora_fm2k/`, `ref_dark_chocolate/`, `fm2ndparser-source/` engine/data
  dumps are local-only (300 MB+); **do not commit**. The `fm2ndparser-source`
  C# files may show as modified (restore artifacts) — ignore.
- Hundreds of untracked `*.import` files under `godot/data/assets/**` are
  generated — ignore, don't stage.
- 🔑 The GitHub PAT used this session was pasted into chat earlier —
  **it must be rotated now** (GitHub → Settings → Developer settings →
  Tokens, revoke + mint a new one), then update `GH_TOKEN` wherever the user
  keeps it.
