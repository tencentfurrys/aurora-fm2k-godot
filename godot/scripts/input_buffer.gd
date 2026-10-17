class_name InputBuffer
extends RefCounted
## FM2K-style frame-indexed input history for one player.
##
## Pure data - no Input/Node coupling, so any control source (keyboard reader,
## demo AI, or a future virtual joystick overlay for the mobile APK build)
## feeds it through the same API:
##   set_axis(m) / press(b) / release(b)  pend state between ticks
##   tick()                               commits one snapshot into the ring
## Combat logic then asks the buffer (axis()/just_pressed()/match_command),
## never the device. Directions are stored RAW (screen-space); command
## direction codes are facing-relative and get mirrored inside the matcher.

const LEN := 96                       # ~1.6 s of history at 60 fps

## raw screen-space direction mask bits (bit order: Left,Right,Down,Up)
const M_LEFT := 1
const M_RIGHT := 2
const M_DOWN := 4
const M_UP := 8

## button mask bits (FM2K: A=weak, B=mid, C=heavy slots; D=4th; E=grab)
const B_A := 1
const B_B := 2
const B_C := 4
const B_D := 8
const B_E := 16
const BTN_ATTACKS := B_A | B_B | B_C

## ComDirection codes compiled into command steps (fm2ndparser enum order)
const CD_FREE := 0                    # any direction
const CD_POINT := 1                   # neutral required (a release)
const CD_RIGHT := 2
const CD_DOWN_RIGHT := 3
const CD_DOWN := 4
const CD_DOWN_LEFT := 5
const CD_LEFT := 6
const CD_UP_LEFT := 7
const CD_UP := 8
const CD_UP_RIGHT := 9
## composites 10-13 match a frame whose axis equals any member direction
const CD_COMP_TOKENS := {
	10: [CD_UP, CD_LEFT, CD_DOWN],    # UpLeftDown
	11: [CD_UP, CD_LEFT, CD_RIGHT],   # UpLeftRight
	12: [CD_UP, CD_RIGHT, CD_DOWN],   # UpRightDown
	13: [CD_DOWN, CD_LEFT, CD_RIGHT], # DownLeftRight
}

## compiled button id (flags1 >> 5) -> button mask
const BTN_ID_MASK := [B_A, B_B, B_C, B_B | B_C, B_D]

var _dir := PackedInt32Array()
var _held := PackedInt32Array()
var _edge := PackedInt32Array()
var _f := 0                           # frames committed; entry _f-1 is newest

# pending feeds (between ticks)
var _p_dir := 0
var _p_held := 0
var _p_edge := 0

func _init() -> void:
	_dir.resize(LEN)
	_held.resize(LEN)
	_edge.resize(LEN)

# ---------------------------------------------------------------- feeds
## Set the absolute axis for the next tick (d-pad or resolved joystick).
func set_axis(mask: int) -> void:
	_p_dir = mask

func press(btn: int) -> void:
	_p_edge |= btn              # every call is a press event (FM2K buttons
	_p_held |= btn              # are edge-triggered; feeders release() between taps)

func release(btn: int) -> void:
	_p_held &= ~btn

## Analog-stick helper for virtual overlays: raw mask from a normalized
## vector and a deadzone.
static func analog(x: float, y: float, deadzone := 0.4) -> int:
	var m := 0
	if x < -deadzone: m |= M_LEFT
	elif x > deadzone: m |= M_RIGHT
	if y < -deadzone: m |= M_UP
	elif y > deadzone: m |= M_DOWN
	return m

## Commit one snapshot; the owner calls this once per physics tick after the
## tick's feeds are pended. Edge flags survive exactly one snapshot.
func tick() -> void:
	var k := _f % LEN
	_dir[k] = _p_dir
	_held[k] = _p_held
	_edge[k] = _p_edge
	_f += 1
	_p_edge = 0

## Drop recent press edges (the owner calls this after launching a skill off
## them, so stale presses can't re-fire when actionability returns).
func consume_edges() -> void:
	_p_edge = 0
	for back in [0, 1]:
		if _f - back > 0:
			_edge[(_f - back) % LEN] = 0

## Drop ALL state (menus call this when a dialog closes so stale held
## buttons or pended axes can't leak back into combat).
func reset() -> void:
	_dir.fill(0)
	_held.fill(0)
	_edge.fill(0)
	_p_dir = 0
	_p_held = 0
	_p_edge = 0

# ------------------------------------------------------------ current state
func axis() -> int:
	return _at(_dir, _f - 1)

func held(btn: int) -> bool:
	return (_at(_held, _f - 1) & btn) != 0

func just_pressed(btn: int) -> bool:
	return (_at(_edge, _f - 1) & btn) != 0

func _at(set: PackedInt32Array, f: int) -> int:
	return set[((f % LEN) + LEN) % LEN]

# -------------------------------------------------------------- FM2K matcher
## Match a compiled command against recent history.
##   cmd {n, time, ls {a,s,sf,c}, steps [{d,b,e,w,cont}]}
## Rules (hand-verified against the Aurora binaries):
##  - last step (cont=false) is the trigger: needs a fresh press edge of its
##    button set; b==0 & !e = weak catch-all (any attack button)
##  - direction steps require that state on a frame, ARRIVING from another
##    state (hold-through cannot fake a sequence); Point needs a release
##  - step n+1 must land within w_n frames of step n's match
##  - the whole run spans <= time frames, all inside the history window
##  - authored directions are facing-relative: Right = "toward the opponent"
func match_command(cmd: Dictionary, facing: int) -> bool:
	var steps: Array = cmd.get("steps", [])
	if steps.is_empty():
		return false
	var trig: Dictionary = steps[steps.size() - 1]
	if bool(trig.get("cont", true)):
		return false                     # no trigger row: not a command
	var time_all := mini(int(cmd.get("time", 60)) + 2, LEN - 2)
	var tmask := _trig_mask(trig)
	var tip := _f - 1
	var tb := tip
	while tb >= tip - time_all and tb >= 0:
		if tmask != 0:
			var e := _at(_edge, tb)
			# catch-all fires on any single attack button; strict sets
			# (e.g. Grab3's B+C) need every listed button pressed that frame
			var hit_edge := (e & BTN_ATTACKS) != 0 if tmask == BTN_ATTACKS \
					else (e & tmask) == tmask
			if not hit_edge:
				tb -= 1
				continue
		if _step_dir_ok(steps[steps.size() - 1], tb, facing):
			if _match_before(steps, steps.size() - 2, tb, facing, time_all):
				return true
		tb -= 1
	return false

## Buttons a step's flag bits map to (for trigger rows, see _trig_mask).
func _flags_mask(st: Dictionary) -> int:
	var b := int(st.get("b", 0))
	var m := 0
	if b > 0 and b < BTN_ID_MASK.size():
		m = BTN_ID_MASK[b]
	if bool(st.get("e", false)):
		m |= B_E
	return m

## Trigger rows: b==0 & !e & d!=0 is a pure-motion trigger (e.g. the dash's
## second tap - no button); b==0 & !e & d==0 is the FM2K weak catch-all
## (any attack button); E adds/is the grab button.
func _trig_mask(st: Dictionary) -> int:
	var m := _flags_mask(st)
	if m == 0:
		if int(st.get("d", 0)) != 0:
			return 0                     # motion-only trigger
		m = BTN_ATTACKS
	return m

## Non-trigger steps with listed buttons require them HELD on the match frame.
func _step_btn_ok(st: Dictionary, f: int) -> bool:
	var m := _flags_mask(st)
	return m == 0 or (_at(_held, f) & m) == m

## Direction condition on frame f (with arrival rule), buttons as well.
func _step_dir_ok(st: Dictionary, f: int, facing: int) -> bool:
	var d := int(st.get("d", 0))
	var req: Variant = _required_mask(d, facing)
	if req is Array:                     # composite: axis equals any member
		var v := _at(_dir, f)
		var ok := false
		for m in req:
			if v == int(m):
				ok = true
				break
		if not ok or _at(_dir, f - 1) == v:
			return false
		return _step_btn_ok(st, f)
	match d:
		CD_FREE:
			return _step_btn_ok(st, f)   # any direction, buttons only
		CD_POINT:
			# neutral state check only: standing itself satisfies a "release"
			# step (the dash's first tap starts from a long neutral stretch)
			if _at(_dir, f) != 0:
				return false
			return _step_btn_ok(st, f)
		_:
			if req == null or int(req) == 0:
				return _step_btn_ok(st, f)
			if _at(_dir, f) != int(req) or _at(_dir, f - 1) == int(req):
				return false
			return _step_btn_ok(st, f)

## Authored ComDirection -> required raw mask (facing-mirrored), or an
## Array of member masks for composite codes.
func _required_mask(d: int, facing: int) -> Variant:
	var fwd := M_RIGHT if facing > 0 else M_LEFT
	var bck := M_LEFT if facing > 0 else M_RIGHT
	match d:
		CD_RIGHT: return fwd
		CD_DOWN_RIGHT: return M_DOWN | fwd
		CD_DOWN: return M_DOWN
		CD_DOWN_LEFT: return M_DOWN | bck
		CD_LEFT: return bck
		CD_UP_LEFT: return M_UP | bck
		CD_UP: return M_UP
		CD_UP_RIGHT: return M_UP | fwd
		_:
			var tokens: Array = CD_COMP_TOKENS.get(d, [])
			if tokens.is_empty():
				return 0
			var faces: Array[int] = []
			for t in tokens:
				var m: Variant = _required_mask(int(t), facing)
				if m is int and not faces.has(int(m)):
					faces.append(int(m))
			return faces

# ----------------------------------------------------- backwards step walk
## Iterative walk from a trigger candidate backwards through every step.
## Step n's match must land within w_n frames before the NEXT step's match
## (distinct frames), and the first step lands within time_all of the
## trigger (whole-sequence span).
func _match_before(steps: Array, idx: int, after: int, facing: int, time_all: int) -> bool:
	if idx < 0:
		return true
	var j := after
	for n in range(idx, -1, -1):
		var st: Dictionary = steps[n]
		var gap_max := mini(int(st.get("w", 20)), time_all)
		var down_to := maxi(j - gap_max, 0)
		var found := -1
		# the step right before the trigger may share the trigger's frame
		# (pressing the button while the last direction is still held)
		var cur := j if n == idx else j - 1
		while cur >= down_to:
			if _step_dir_ok(st, cur, facing):
				found = cur
				break
			cur -= 1
		if found < 0:
			return false
		j = found
	if after - j > time_all:
		return false                     # whole sequence spans too long
	return true
