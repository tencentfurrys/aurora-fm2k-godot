extends Node2D
## Headless v0.4 regression: InputBuffer matcher units + commanded specials +
## chain cancels through the fighter's real poll path. Prints
## INPUT-TEST-PASS / INPUT-TEST-FAIL.

const FIGHTER := preload("res://scripts/fighter.gd")

var t := 0
var p1: Fighter
var p2: Fighter
var errors: Array[String] = []

# ---------------------------------------------------------------- setup
func _ready() -> void:
	p1 = FIGHTER.new()
	add_child(p1)
	p1.setup("Applejack", 0)
	p1.manual_input = true        # the test is the control source (overlay hook)
	p1.pos.x = 120
	p2 = FIGHTER.new()
	add_child(p2)
	p2.setup("Applejack", 1)
	p2.pos.x = 380               # far: phase A's applebuck must whiff
	p1.opp = p2
	p2.opp = p1

# ---------------------------------------------------------------- helpers
func _feed_seq(buf: InputBuffer, seq: Array) -> void:
	for m in seq:
		buf.set_axis(m)
		buf.tick()

# ------------------------------------------------------------ phase 0: units
func _phase_units() -> void:
	var weak := {"n": "W", "time": 10, "ls": {}, "steps": [{"d": 0, "b": 0, "e": false, "w": 20, "cont": false}]}
	var mid := {"n": "M", "time": 10, "ls": {}, "steps": [{"d": 0, "b": 1, "e": false, "w": 20, "cont": false}]}
	var grab_bc := {"n": "G", "time": 10, "ls": {}, "steps": [{"d": 0, "b": 3, "e": false, "w": 20, "cont": false}]}
	var qcf := {"n": "AB", "time": 25, "ls": {}, "steps": [
		{"d": 4, "b": 0, "e": false, "w": 20, "cont": true},
		{"d": 3, "b": 0, "e": false, "w": 20, "cont": true},
		{"d": 2, "b": 0, "e": false, "w": 20, "cont": true},
		{"d": 0, "b": 0, "e": false, "w": 20, "cont": false}]}
	var dash := {"n": "D", "time": 20, "ls": {}, "steps": [
		{"d": 1, "b": 0, "e": false, "w": 20, "cont": true},
		{"d": 2, "b": 0, "e": false, "w": 20, "cont": true},
		{"d": 1, "b": 0, "e": false, "w": 20, "cont": true},
		{"d": 2, "b": 0, "e": false, "w": 20, "cont": false}]}

	# weak catch-all fires on A; strict B does not match A; B+C needs BOTH
	var b := InputBuffer.new()
	b.tick()
	b.press(InputBuffer.B_A)
	b.tick()
	if not b.match_command(weak, 1):
		errors.append("unit: weak catch-all no match")
	if b.match_command(mid, 1):
		errors.append("unit: strict B matched A press")
	if b.match_command(grab_bc, 1):
		errors.append("unit: B+C matched single A press")
	b.press(InputBuffer.B_B)
	b.tick()
	if not b.match_command(mid, 1):
		errors.append("unit: mid no match after B")

	# qcf + C, and the mirrored feed for facing -1
	var b2 := InputBuffer.new()
	_feed_seq(b2, [0, InputBuffer.M_DOWN, InputBuffer.M_DOWN | InputBuffer.M_RIGHT, InputBuffer.M_RIGHT])
	b2.press(InputBuffer.B_C)
	b2.tick()
	if not b2.match_command(qcf, 1):
		errors.append("unit: qcf+C no match")
	if b2.match_command(qcf, -1):
		errors.append("unit: qcf matched for wrong facing")

	var b3 := InputBuffer.new()
	_feed_seq(b3, [0, InputBuffer.M_DOWN, InputBuffer.M_DOWN | InputBuffer.M_LEFT, InputBuffer.M_LEFT])
	b3.press(InputBuffer.B_C)
	b3.tick()
	if not b3.match_command(qcf, -1):
		errors.append("unit: mirrored qcf no match")

	# qcf without the trigger button must not fire
	var b6 := InputBuffer.new()
	_feed_seq(b6, [0, InputBuffer.M_DOWN, InputBuffer.M_DOWN | InputBuffer.M_RIGHT, InputBuffer.M_RIGHT])
	b6.tick()
	if b6.match_command(qcf, 1):
		errors.append("unit: qcf fired without button")

	# motion-only trigger (dash): neutral, tap, release, tap
	var b9 := InputBuffer.new()
	_feed_seq(b9, [0, InputBuffer.M_RIGHT, 0, InputBuffer.M_RIGHT])
	if not b9.match_command(dash, 1):
		errors.append("unit: tap-tap dash no match")
	var b10 := InputBuffer.new()
	_feed_seq(b10, [0, InputBuffer.M_RIGHT, InputBuffer.M_RIGHT, InputBuffer.M_RIGHT])
	if b10.match_command(dash, 1):
		errors.append("unit: hold-through faked a dash")

	# span caps: gaps of 15 make the whole run exceed time 25 (+2)
	var b11 := InputBuffer.new()
	b11.set_axis(InputBuffer.M_DOWN)
	b11.tick()
	for i in 15:
		b11.tick()
	b11.set_axis(InputBuffer.M_DOWN | InputBuffer.M_RIGHT)
	b11.tick()
	for i in 15:
		b11.tick()
	b11.set_axis(InputBuffer.M_RIGHT)
	b11.press(InputBuffer.B_C)
	b11.tick()
	if b11.match_command(qcf, 1):
		errors.append("unit: stale qcf past time window matched")
	# legal gaps of 8 still match
	var b12 := InputBuffer.new()
	b12.set_axis(InputBuffer.M_DOWN)
	b12.tick()
	for i in 8:
		b12.tick()
	b12.set_axis(InputBuffer.M_DOWN | InputBuffer.M_RIGHT)
	b12.tick()
	for i in 8:
		b12.tick()
	b12.set_axis(InputBuffer.M_RIGHT)
	b12.press(InputBuffer.B_C)
	b12.tick()
	if not b12.match_command(qcf, 1):
		errors.append("unit: paced qcf (8f gaps) no match")

# ------------------------------------------------------------- phase drivers
var pressed_chain := false
var pressed_chain2 := false
var ok_special := false
var ok_weak := false
var ok_chain := false
var ok_chain2 := false

func _physics_process(_d: float) -> void:
	t += 1
	if t == 5:
		_phase_units()
	# ---- phase A: qcf + A -> Applebuck L (weak catch-all; no travel) ----
	if t == 50:
		p1.ibuf.set_axis(InputBuffer.M_DOWN)
	if t == 51:
		p1.ibuf.set_axis(InputBuffer.M_DOWN | InputBuffer.M_RIGHT)
	if t == 52:
		p1.ibuf.set_axis(InputBuffer.M_RIGHT)
	if t == 53:
		p1.ibuf.set_axis(InputBuffer.M_RIGHT)
		p1.ibuf.press(InputBuffer.B_A)
	if t == 58:
		ok_special = p1.skill_idx == 230
		if not ok_special:
			errors.append("phase A: applebuck not launched (skill=%d state=%s)" % [p1.skill_idx, p1.state])
	if t == 60:
		p1.ibuf.set_axis(0)            # restore a neutral pend for later phases
	# ---- phase B: weak press -> Standing Light, connect, chain to Mid ----
	if t == 112:
		p1.pos.x = 120                 # undo any drift; p2 just inside light reach
		p2.pos.x = 185
	if t == 114:
		p1.ibuf.press(InputBuffer.B_A)
	if t == 124:
		ok_weak = p1.skill_idx == 196 and p1.hit_done
		if not ok_weak:
			errors.append("phase B: light not launched/connected (skill=%d hit_done=%s)" % [p1.skill_idx, p1.hit_done])
	if t >= 120 and t <= 126 and not pressed_chain:
		# buffered press just before the light's cancel window (skill_t 11..14)
		if p1.state == "ACT" and p1.skill_t >= 9:
			pressed_chain = true
			p1.ibuf.press(InputBuffer.B_B)
	# ---- phase C: chain to Standing Heavy inside mid's hits window ----
	if t >= 124 and t <= 150:
		p2.pos.x = p1.pos.x + 65.0     # pin victim for deterministic connects
	if t >= 136 and t <= 146 and not pressed_chain2:
		# mid's second cancel row: skill_t 13..30 (with hits)
		if p1.state == "ACT" and p1.skill_idx == 197 and p1.skill_t >= 13 and p1.hit_done:
			pressed_chain2 = true
			p1.ibuf.press(InputBuffer.B_C)
	if t == 135:
		ok_chain = p1.skill_idx == 197
		if not ok_chain:
			errors.append("phase B: chain to Standing Mid failed (skill=%d skill_t=%d)" % [p1.skill_idx, p1.skill_t])
	if t == 146:
		ok_chain2 = p1.skill_idx == 198
		if not ok_chain2:
			errors.append("phase C: chain to Standing Heavy failed (skill=%d skill_t=%d)" % [p1.skill_idx, p1.skill_t])
	if t == 170:
		print("INPUT result: special=%s weak=%s chain=%s chain2=%s" % [ok_special, ok_weak, ok_chain, ok_chain2])
		if errors.is_empty():
			print("INPUT-TEST-PASS")
		else:
			for e in errors:
				print("  FAIL: ", e)
			print("INPUT-TEST-FAIL")
		get_tree().quit()
