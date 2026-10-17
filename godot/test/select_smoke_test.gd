extends Node2D
## Headless smoke for the select screen v0.8 behaviors: stage-pick preview
## draws the compiled stage art from phase 2 (and the ready screen), and the
## touch tap flow mirrors the keys: tap = cursor, tap-highlighted = confirm,
## stage halves cycle, middle band confirms.

var t := 0
var v: Node2D
var tap_p1 := false
var tap_p2 := false
var tap_stage := false
var preview_ok := false
var roster_ok := false

func _ready() -> void:
	var sc: PackedScene = load("res://scenes/select.tscn")
	v = sc.instantiate()
	add_child(v)

func _physics_process(_d: float) -> void:
	t += 1
	if v == null:
		return
	if t == 5:
		roster_ok = v.roster.size() >= 18 or v.roster.size() >= 16
	# stage phase: preview must show compiled art and survive cycling
	if t == 6:
		v.phase = 2
		v._cycle_stage(5)
		preview_ok = v._stage_prev.visible and v._stage_prev.texture != null
	# tap flow: tile place + tap-highlighted confirm (two taps on tile 3)
	if t == 7:
		v.phase = 0
		v._touch_tap(v.origins[3] + Vector2(22, 22))
	if t == 8:
		v._touch_tap(v.origins[3] + Vector2(22, 22))
		tap_p1 = v.phase == 1 and v.p1_pick == 3
		v._touch_tap(v.origins[3] + Vector2(22, 22))
		tap_p2 = v.phase == 2 and v.p2_pick == 3
	# stage taps: left third cycles back, right third cycles forward, middle
	# band confirms
	if t == 9:
		var s0: int = v.cur_stage
		v._touch_tap(Vector2(50, 120))
		var s1: int = v.cur_stage
		v._touch_tap(Vector2(260, 120))
		tap_stage = s1 != s0 and v.cur_stage == s0
		v._touch_tap(Vector2(160, 50))
	if t == 10:
		var ready_ok: bool = v.phase == 3 and preview_ok and tap_p1 \
				and tap_p2 and tap_stage and roster_ok
		print("SEL-SMOKE RESULT: roster=%s preview=%s tap_p1=%s tap_p2=%s tap_stage=%s ready=%s" % [
			roster_ok, preview_ok, tap_p1, tap_p2, tap_stage, v.phase == 3])
		print("SEL-SMOKE-PASS" if ready_ok else "SEL-SMOKE-FAIL")
		get_tree().quit()
