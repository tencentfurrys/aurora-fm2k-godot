# Aurora FM2K → Godot bridge (v0.8)

A Godot 4.3+ project that runs Fighting is Magic: Aurora game data extracted
from the original FM2K (2D Fighter Maker 2002) files, using compiled JSON
produced by `tools/fm2k_compile.py`.

## Running it

1. Install [Godot 4.3+](https://godotengine.org/download) (standard build).
2. Open this folder (`godot/`) as a project in Godot.
3. Press F5 (Run Project).

Pressing F5 boots the **title screen** → **character select** (pick P1, then
P2, then a stage from the 27 compiled stages) → the fight. The fight scene
can also be booted directly: empty parameters load `data/manifest.json` →
first two characters vs each other, P2 running a small demo brain that feeds
the same input buffer a human uses (walks, jumps back and forth, attacks
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

Menus (title / character select / victory screen): **Enter** = confirm,
**Esc** = back, **arrows** = navigate (roster grid + stage cycle). **Esc**
during a fight opens the pause menu (authored `Pause` word art; Resume /
Character select). **D** guards on its own now (authored `buttonGuard*`
poses, same junctions as holding back), and a grabbed victim taps **E**
inside the connect window to FM2K-throw-break ('Grab Broken', no damage).
Touch/mouse taps work everywhere (title tap → select; select taps place
cursors, tap a highlighted tile to confirm, stage halves cycle / middle
band confirms); the **virtual touch pad** shows automatically on touch
hardware or via the mouse-emulation setting (F3 toggles). Rounds are
best-of-3 (first to 2 round wins) with the authored 99-count timer;
time-out awards the round to whoever has more health. Wins show as
authored victory marks next to the life gauges.

Hold **back** (away from the opponent) to guard — low guard = back+down,
air guard = back in mid-air. Blocked hits chip ~20% damage. Connects freeze
both fighters briefly (hitstop). Supers need spirit gauge: Level 1 = 1/3
bar, Level 3 = full bar.

P2 uses arrow keys + Numpad 1/2/3 (A/B/C) and Numpad 4/5 (D/E).

All buttons are edge-triggered through the command matcher: a plain press
plays the basic, motion+button inputs launch specials/supers (e.g.
`Down, Down-Right, Right + A` = Applebuck, `Right+Right` = dash).

## What's new in v0.8 — touch overlay, authenticity pass, engine details

- **Virtual FM2K touch pad** (`scripts/touch_controls.gd`): left d-pad stick
  + the five-button arcade arc, feeding the same `InputBuffer` as a keyboard
  (8-way axis through `InputBuffer.analog`, press/release edges) — the
  mobile-APK target input. Auto-shows on touch devices or mouse-emulation
  installs; F3 toggles; `emulate_touch_from_mouse` is on in project
  settings so desktops can play it with the mouse. Title/select gained
  touch taps (tile-tap-to-confirm; stage halves cycle).
- **Authentic menus**: the compiled scene dumps now feed the shell — the
  *real* MLP: Fighting Is Magic Aurora title art drives the title screen and
  the character-select backdrop; the select grid uses the authored
  per-fighter select tiles (50×44) from the "Character Select" dump, with
  the six mains sliced out of the authored Mane-6 sheet (2×3 atlas), plus
  the select screen's own logo. Demo bank compiled to `data/demos/`
  (Credits, Continue, Options, Epilogue, Character Select, Title).
- **Guard button (D)**: authored `buttonGuardStand/Crouch/Air` builtins
  carry the pose; on guard it resolves the same junction rows as holding
  back — hold-back guard coexists (stand/back-walk, low, air).
- **Throw break (FM2K)**: a grabbed victim tapping the grab button **E**
  within the connect window escapes via junction 96 `Grab Broken` (all 20
  fighters carry it) — toss never happens, no damage, attacker cut back to
  neutral. Headless regressions: `touch_test` (stick axis + edges +
  multi-finger), `guard_test` stage 2 (button guard), `throw_test` stage 2
  (break window), `match_test` stage 2 (continue screen boot + rematch).
- **Continue screen (v0.8)**: lose the demo-AI match and the authentic
  "Don't give up now!" art takes over with the FM2K 9-count — Enter/tap =
  YES (full rematch, Round 1 again), Esc/timeout = NO (game over back to
  the title), with the dump's own voice clip.

## What's new in v0.7 — game shell: title, character select, round flow

The whole shell is data-driven off the **authored KGT UI bank** (`kgt.json`,
226 named skills — screens, HUD kit, announcer cards, voice clips):

- **Boot flow**: `scenes/title.tscn` (hex backdrop img 2000 + authored K.O.
  plaque img 22) → `scenes/select.tscn` — portraits come from each fighter's
  authored `charSelectPic` (fallback: standing pose frame where the select
  art lives in the un-banked 8191 image slot) — pick P1, pick P2, pick any
  of **27 compiled stages** (the full stage roster in the corpus; the
  `Ponyville Plaza` parse dump is missing from the backup, it stays out) →
  fight. The fight scene takes picks via static params and falls back to the
  manifest demo boot.
- **Round/match flow**: fighters are round-flow locked through the announcer
  chain and thaw exactly on the `Fight` card: `Round N` / `Final Round` (the
  FM2K card set, imgs 281–310) → `Fight` (imgs 276–279) → on stoppage
  `Knock Out` / `Double Knock Out` (+ `Perfect` when the winner took no
  damage) → `1P Wins` / `2P Wins` / `Draw` → next round or match end with the
  winner playing its own authored **Victory** builtin on the loser's loss
  pose. FM2K rules: first to 2 rounds, plus the authored 99-count round timer
  with its digit images (239–248) and a `TIME'S UP` hp-tiebreak.
- **Authentic HUD**: authored life gauge art (imgs 130/131) over health
  fills, spirit gauge fills, and the authored victory marks (imgs 132/133)
  as round-win pips. Announcer voice clips (Round/Fight/Perfect/Draw) play
  from the authored sound events.
- **Pause menu**: Esc during a fight freezes both fighters over the authored
  `Pause` word skill with Resume / Character-select options.
- Headless regressions: `match_test` drives the real main scene through two
  KOs end-to-end (cards, reset, wins, victory pose); `stage_test` proves the
  whole compiled roster renders (27 stages + 21 fighters, json → PNG).

## What's new in v0.6 — guard, throws, hitstop, spirit gauge

- **Guard**: holding back (relative to the opponent) while neutral guards —
  back walk = stand guard, back+down = low guard (plays the crouching walk
  while held), back in the air = air guard. Blocked connects resolve the
  attack's authored **guard junctions** (R-block `gs/gc/ga` rows, e.g.
  `Guard  WK Standin` + `Block Spark`; note the authored guard-crush rows
  that point heavy attacks into the knockdown junctions are respected).
  Guarded damage is chip: FA power × rate × 8 × 0.2 (no authored ratio in
  the tables; tunable).
- **Throws**: grabs are ordinary commands (`Grab (Right + E)` = fwd arrival
  + E tap — holding forward then tapping never satisfies the authored
  trigger row) launching skills 209/210. Their `thr`+`dmg` reach boxes
  connect at body adjacency against the victim's idle hurt zones and force
  the victim into the fixed FM2K junction 95 `Grabbed` skill; the attacker's
  own authored frames carry the buck toss. Thrown victims ride the
  knockdown → wake-up flow back to standing. Throw-breaks (junction 96
  `Grab Broken`) are authored but not implemented yet.
- **Hitstop** (`stiffTime` freeze): attacker and victim both freeze for 10
  ticks on connect (6 on guarded hits), anim/physics/combat all held, input
  ring keeps ticking so buffered inputs stay accurate. Barely-authored in
  the compiled blocks; engine-wide fixed values for now.
- **Spirit gauge** (FM2K meter): filled from the authored `settings.meter`
  (160 on Applejack). Dealing damage feeds the attacker's gauge, taking
  damage feeds ~60% of it to the victim; guarded connects feed the chip.
  Super commands named `(Level 1)` / `(Level 3)` in the authored tables
  cost 1/3 of the gauge / the full gauge and are skipped when short, exactly
  like the FM2K runtime falling through to the next command row. HUD shows
  both gauges under the life bars.
- Headless regression: `guard_test` (blocked reaction + chip + guard
  hitstop), `meter_test` (Level 1 gated → launched → gauge spent; Level 3
  stays out of reach), `throw_test` (grab → Grabbed junction → wake-up →
  standing); `input_test` chain phases reworked to be condition-driven -
  hitstop shifts the timeline, so fixed-tick asserts no longer hold.

## What's new in v0.5 — knockdown & wake-up

- **Knockdown flow**: junction gethit skills whose authored names are FM2K down
  states (`Knocked Down Light/Mid/Heavy/Mid Corner`, `Face Knockdown`,
  `Hard Knockdown Back/Face/Front`, `Back Knockdown`, `Wall Hit`) end in the
  authored lying/down-time hold instead of snapping back to standing (v0.2
  wake-up proxy removed). Victim juggling still applies while lying
  (their gethit FD hurt boxes stay live).
- **Wake-up** uses every character's *own* authored recovery skill. Names are
  spelled inconsistently across the roster (`Fall Down Get Up` on Applejack,
  `Fall Down Getup Face` on Twilight/final boss, `Get Up`/`Getup`/`GetUp`
  spacing variants), so wakeup lookup normalizes spaces/caps and falls back
  across variants: standard down-time → `Fall Down Get(Up| )…` → `Getup Face`;
  face knockdowns → `Getup Face`; back knockdowns → `GetUp Back`.
- **Airborne knockdowns** (M-block launches that are still in the air when
  their frames end) stay in the reaction on the lying last frame; the wake-up
  fires on the physics landing (via the `landed` spike).
- `data/manifest.json` now covers the whole `--all` roster (20 fighters with
  down states + the Mode Select dummy). Headless regression:
  `godot/test/knockdown_test.tscn` asserts knockdown → wake-up skill →
  standing, plus wake-up discovery over the compiled roster.

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

- Knockdown / wake-up core flow (v0.5: reaction end → authored recovery skill;
  still missing: okizeme timing nuances, down-time escape/roll, wall-bounce
  corner variants that re-launch mid-air after the down hold)
- Throw/grab connect logic (v0.6: grab connect -> junction `Grabbed` -> toss
  -> knockdown works; still missing: throw-breaks/escape, neutral-start
  grab whiff animation handling)
- Hitstop (`stiffTime` freeze v0.6: fixed 10/6-tick freeze on both; per-move
  authored stiffTime values are not in the compiled blocks)
- Guard/blocking (v0.6: hold-back guard + guard junctions + chip; still
  missing: guard button builtins, guard-crush meters, block pose details,
  chip KO (blocked damage currently cannot reduce to KO))
- Meter gating for Level 1/3 super commands (v0.6: authored `settings.meter`
  gauge with 1/3 + full-bar costs; still missing: per-move meter tuning,
  gauge overflow rules, aerial super refs)
- Title/select/round shell (v0.7+v0.8: full boot flow, announcer chain,
  first-to-2 rounds + timer + pause menu + touch taps + FM2K continue
  screen + authored title and select art from the compiled scene dumps;
  still missing: the dumped screens' full scene *scripts* aren't emulated —
  the shell uses their art banks with Godot-native layouts — mouse-free
  cursor keybind display, character-select portraits live in the un-banked
  8191 slot for the mains (the Mane-6 sheet + standing poses stand in),
  and the missing `Ponyville Plaza` stage dump)
- Mobile APK packaging/export presets (the touch overlay itself shipped in
  v0.8; `InputBuffer.analog()` shapes the stick vector)
- Air hitstun/juggle physics, palette variants

## Headless tests

```powershell
$godot = "..\Godot_v4.3-stable_win64_console.exe"
& $godot --headless --path . res://test/input_test.tscn     # v0.4: INPUT-TEST-PASS
& $godot --headless --path . res://test/hit_test.tscn       # v0.2/0.3: HIT-TEST-PASS + KO-TEST-PASS
& $godot --headless --path . res://test/knockdown_test.tscn # v0.5: KD-TEST-PASS
& $godot --headless --path . res://test/guard_test.tscn     # v0.6: GUARD-TEST-PASS
& $godot --headless --path . res://test/meter_test.tscn     # v0.6: METER-TEST-PASS
& $godot --headless --path . res://test/throw_test.tscn     # v0.6: THROW-TEST-PASS
& $godot --headless --path . res://test/match_test.tscn     # v0.7: MATCH-TEST-PASS (+ v0.8 continue stage)
& $godot --headless --path . res://test/stage_test.tscn     # v0.7: STAGE-TEST-PASS
& $godot --headless --path . res://test/touch_test.tscn     # v0.8: TOUCH-TEST-PASS
& $godot --headless --path . --quit-after 400               # boot smoke (title)
```

(Add a new `class_name` script → run `--headless --import` once so the class
DB picks it up.)
