# Aurora FM2K → Godot bridge (v0.4)

A Godot 4.3+ project that runs Fighting is Magic: Aurora game data extracted
from the original FM2K (2D Fighter Maker 2002) files, using compiled JSON
produced by `tools/fm2k_compile.py`.

## Running it

1. Install [Godot 4.3+](https://godotengine.org/download) (standard build).
2. Open this folder (`godot/`) as a project in Godot.
3. Press F5 (Run Project).

The game boot scene loads `data/manifest.json` → first two characters vs each
other on the first compiled stage. P2 runs a small demo brain that feeds the
same input buffer a human uses (walks, jumps back and forth, attacks
occasionally).

## Controls (P1)

| Key | Action |
|-----|--------|
| A / D | walk left / right |
| W | jump |
| S | crouch |
| J / K / L | attack A / B / C |
| U | E button (grabs: `Right + E`) |
| I | D button (dodge/counter commands) |
| F1 | toggle hitbox debug overlay |
| R | reset round after K.O. |

P2 uses arrow keys + Numpad 1/2/3 (A/B/C) and Numpad 4/5 (D/E).

All buttons are edge-triggered through the command matcher: a plain press
plays the basic, motion+button inputs launch specials/supers (e.g.
`Down, Down-Right, Right + A` = Applebuck, `Right+Right` = dash).

## What's new in v0.4 — commands, buffered inputs, chain cancels

- **Command records fully decoded** (raw 82-byte entries in the `.player`
  files, parsed by the compiler rather than fm2ndparser, whose button fields
  are mislabeled):
  `[32-byte name][u16 time][4×u16 skill refs][10×(flags1,flags2)][10×u16 Amount]`.
  flags1 low nibble = direction code (Free/Point/8 ways/composites), bits 5–7
  = button id (0 = catch-all, 1 = B, 2 = C, 3 = B+C, 4 = D); flags2 bit0 = E
  (grab) button, bit1 = **disabled** (the 4 `Debug-*` cheat commands are
  skipped); bit4 of flags1 = continue (false = trigger row, everything after
  is junk and truncated). `Amount` = per-step window in frames, `time` =
  whole-sequence deadline.
- **Directions are authored facing-relative**: `Right` means "toward the
  opponent"; the matcher mirrors L↔R / DR↔DL / UL↔UR per fighter facing, so
  one command covers both sides like the original.
- **Trigger rules**: the last `cont=false` row is the trigger;
  `b==0` without E = catch-all (any of A/B/C); E adds the E button; strict
  button sets (e.g. B+C) require every listed button on the edge frame.
  Motion-only triggers (no button, e.g. Forward Dash = `6 5 6 5` taps) scan
  for direction arrivals. Authored list order is priority: supers → specials
  (H→M→L) → grabs → engine basics (`Weak`/`Mid`/`Heavy`) → dashes.
- **Basics are ordinary commands**: `Weak`/`Mid`/`Heavy` = single-step
  catch-alls (time=10), so one unified matcher covers basics, air attacks and
  specials. A command launches the state-suitable skill ref
  (air / stand / stand-far beyond 140px / crouched); ref 0 skips to the next
  command.
- **`InputBuffer`** (`scripts/input_buffer.gd`): a pure-data RefCounted ring
  (96 frames) of axis / held / press-edge snapshots with the FM2K sequence
  matcher:
  - direction steps need an *arrival* (state change into the direction —
    holding through can't fake a sequence); `Point` (=release) steps match a
    neutral frame, standing itself satisfies the first release;
  - step n+1 must land within `w_n` frames of step n; the whole run spans
    ≤ `time`(+2) frames;
  - the step before the trigger may share the trigger's frame (button while
    the last direction is held); press edges survive ~one `time` window, so
    pressess pressed during recovery fire lazily when actionable.
- **`manual_input` contract**: set `fighter.manual_input = true` and the
  owner feeds `fighter.ibuf` directly (press/release/set_axis/tick) — this is
  the hook a virtual touch joystick will use later (`InputBuffer.analog()`
  converts a normalized stick vector to the axis mask). P2's demo brain uses
  the exact same path, so every test exercises it.
- **C-block chain cancels**: `skills[i].cancels[]` rows `{from, to, hits,
  uncond}` are **skill-tick windows** (not frame indices); while an attack is
  inside a window (and connected, for `hits` rows), the command set is live
  again → button chains (L→M→H) and buffered special inputs work mid-attack.
  Dead rows (`!hits && !uncond`) are dropped by the compiler; `skill=0 +
  levelCancel` rows mean "cancel by pressing the next button level".
- Sounds decode fixed for Godot 4.3 (`StreamPeerBuffer` has no
  `get_length`/`get_bytes` → use the byte array directly).
- Headless regression: `godot/test/input_test.tscn` — matcher units (strict
  B+C, mirror facing, hold-through anti-fake, span caps, staged gaps) plus a
  full play phase: qcf+A special → buffered weak press → connect → chain L→M→H
  through real cancel windows.

## What's new in v0.3 — junction hit reactions & sparks

- **R blocks** compiled as `skills[i].reactions = {hs, hc, ha, gs, gc, ga}` —
  the FM2K junction index per victim state (hit stand/crouch/air + guards).
- **FA blocks** compiled as `skills[i].farces[]` events
  `{t, n, x, y, w, h, pw, cc, cb}` — the FM2K attack-force area. `pw` (FA
  power) is the real damage source: WK/Mid/Heavy bucks = 7/13/16.
- **Damage** = `power × FD rate/100 × 8` (weak attacks scale to ~11% of the
  515 HP gauge; legacy `20 + level` fallback if a move has no FA).
- **Junction gethit replay**: attack R-block junction → victim's
  `junctions[j]` → the victim plays **its own gethit skill**
  (e.g. Applejack `Hit    WK Standin` skill #64) with its authored M-block
  knockback physics. HIT state auto-recovers to standing when the reaction
  ends (real knockdown/wake-up flow still pending).
- **Junction sparks**: the same junction entry's spark skill index spawns an
  animated FM2K effect (`effect.gd`) at the contact point from the victim's
  own image/sound banks (`Hitspark 1` = skills #182+ per character).
- Headless regression: `godot/test/hit_test.tscn` asserts hit connect →
  junction gethit skill actually runs → KO.

## What's new in v0.2 — hitboxes & damage

- **FD-block boxes**: compiled into `skills[i].boxes[]` events
  `{t, n:slot, x, y (bottom, height above ground), w, h, col, dmg, thr, rate}`;
  applied to a live 10-slot map at frame starts just like FM2K does.
- **FM2K coordinate model** (empirically calibrated, 95.6% joint sprite/box
  coverage over Applejack + Rainbow Dash, see `tools/model_fit.py`):
  sprite canvas centers sit **88px above the ground line** (`GROUND_TO_ANCHOR`),
  boxes are **bottom-anchored** at `box.y` above the ground plane, x centered
  on the anchor and mirrored when facing left.
- **Combat rules** (matching observed FM2K data semantics):
  - boxes flagged `collide` make bodies solid → push apart while grounded;
  - a **command-launched attack skill's** `damaged` boxes connect against the
    opponent's passive `damaged` boxes (idle hurt zones), once per skill
    instance (`hit_done` reset on skill entry).
- **Hit reactions**: knockback away from the attacker + 24-tick hitstun state
  (real FM2K junction gethit animations replay is v0.3).
- **K.O.**: at 0 HP the fighter plays the builtin `loss` skill and both input
  and combat lock; HUD shows "K.O." and R resets the round.
- **F1 debug overlay**: red = solid, blue = hurt, green = throw.
- Headless regression test: `godot/test/hit_test.tscn` (hit connect + KO flow).

## What drives the character data

- `data/characters/<slug>.json` — compact compiled skill data:
  - `skills[i].frames[]` — animation frames `{i: imageId, x, y, d}` (walked exactly like FM2K skill block lists)
  - `skills[i].moves[]` — FM2K `M` blocks: movement/velocity/gravity events
  - `skills[i].sounds[]` — FM2K `S` blocks: sound events
  - `skills[i].boxes[]` — FM2K `FD` blocks: hitbox slot events
  - `skills[i].farces[]` — FM2K `FA` blocks: attack-force (damage + push) events
  - `skills[i].reactions` — FM2K `R` block: junction indices per victim state
  - `skills[i].cancels[]` — FM2K `C` blocks: chain-cancel windows (skill-ticks;
    consumed by `fighter._poll_cancels`)
  - `skills[i].lvl` — skill level (attack damage + junction index)
  - `junctions[]` — per-level hit junction + spark names (name-keyed; the
    numbers do NOT index KGT skills)
  - `builtin` — the FM2K builtin motion map
  - `commands[]` — FM2K command inputs decoded from raw bytes:
    `{n, time, ls:{a,s,sf,c}, steps:[{d,b,e,w,cont}]}`; engine basics
    (`Weak`/`Mid`/`Heavy`) are ordinary catch-all commands in the same list
- `data/kgt.json` — KGT common skills (menus/layout art, 340 images); note the
  hit-spark/gethit junction skills live in KGT binary sections the parser does
  not decode yet.
- `data/assets/<slug>/img/*.png` — extracted sprites (imported from original FMX1985 palettes)
- `data/assets/<slug>/snd/*.wav` — extracted sounds

## Regenerating data

```powershell
# from repo root
python tools/fm2k_compile.py                # Applejack + Rainbow Dash + Training Stage + KGT
python tools/fm2k_compile.py --all          # every character + stages
python tools/fm2k_compile.py --char "Luna" --stage "Ponyville"
```

Source of truth: `..\aurora_fm2k\` (raw `.player` binaries; command rows are
decoded by the compiler — fm2ndparser's command section is unreliable).

## Not yet implemented

- Throw/grab connect logic (the `E`-button grab commands launch skill 210;
  the actual throw unify/victim-toss flow is missing)
- Knockdown / wake-up (hit reactions currently recover standing; the
  `S`-block down states are next)
- Hitstop (`stiffTime` freeze frames)
- Guard/blocking + chip damage (`gs/gc/ga` junction refs compiled, unused)
- Meter gating for Level 1/3 super commands
- Virtual touch overlay: speaks `manual_input` + `InputBuffer` (the mobile
  APK target); `InputBuffer.analog()` already shapes a stick vector
- Air hitstun/juggle physics, palette variants, rounds/match flow

## Headless tests

```powershell
$godot = "..\Godot_v4.3-stable_win64_console.exe"
& $godot --headless --path . res://test/input_test.tscn   # v0.4: INPUT-TEST-PASS
& $godot --headless --path . res://test/hit_test.tscn     # v0.2/0.3: HIT-TEST-PASS + KO-TEST-PASS
& $godot --headless --path . --quit-after 400             # boot smoke
```

(Add a new `class_name` script → run `--headless --import` once so the class
DB picks it up.)
