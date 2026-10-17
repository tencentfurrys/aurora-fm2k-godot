extends Node2D
## Headless throw regression. Command flow under test: "Grab (Right + E)"
## (fwd direction + E button) launches the authored grab skill ('Grab2' #210);
## its thr+dmg reach box connects against the victim's idle hurt zones, forcing
## the victim into junction 95 'Grabbed' (#82), whose frames end in the
## knockdown -> wake-up flow (down states) and back to standing.

const FIGHTER := preload("res://scripts/fighter.gd")

var t := 0
var p1: Fighter
var p2: Fighter
var saw_grab_skill := false
var saw_grabbed := false
var saw_stand := false
var b_connect := false
var b_broken := false
var b_freed := false
var stage1_ok := false

func _ready() -> void:
	Data.reset_for_tests()
	p1 = FIGHTER.new()
	add_child(p1)
	p1.setup("Applejack", 0)
	p1.pos.x = 120
	p2 = FIGHTER.new()
	add_child(p2)
	p2.setup("Applejack", 1)
	p2.pos.x = 185
	p1.opp = p2
	p2.opp = p1
	p2.ai = false

func _physics_process(_d: float) -> void:
	t += 1
	if t == 40:
		p1.manual_input = true
		# FM2K grabs connect at body adjacency: walking stops where the col
		# boxes touch (~30px apart); any farther and the reach whiffs
		p1.pos.x = p2.pos.x - 33.0
		print("TEST: grab distance = ", absf(p2.pos.x - p1.pos.x))
	if t == 42:
		# FM2K grab trigger: the fwd direction ARRIVAL carries the E tap
		# (holding fwd then tapping never satisfies the authored [2,0,1])
		p1.ibuf.set_axis(InputBuffer.M_RIGHT)
		p1.ibuf.press(InputBuffer.B_E)
	if t == 44:
		p1.ibuf.set_axis(0)
	if t == 160 and not saw_grab_skill:
		print("TEST: grab not seen yet, retry point blank")
		p1.pos.x = p2.pos.x - 33.0
		p1.ibuf.set_axis(InputBuffer.M_RIGHT)
		p1.ibuf.press(InputBuffer.B_E)
	if t > 46 and t <= 900:
		if not saw_grab_skill and (p1.skill_idx == 210 or p1.skill_idx == 209):
			saw_grab_skill = true
			var g: Dictionary = p1.skill_by_index.get(p1.skill_idx, {})
			print("TEST: grab launched (t=", t, ") skill='", g.get("n"), "'")
		elif saw_grab_skill and not saw_grabbed and p2.state == "HIT":
			var sk: Dictionary = p2.skill_by_index.get(p2.skill_idx, {})
			if String(sk.get("n", "")).begins_with("Grabbed"):
				saw_grabbed = true
				print("TEST: victim 'Grabbed' junction (t=", t, ") skill_idx=",
						p2.skill_idx, " wake-up pending after toss")
		elif saw_grabbed and not saw_stand and p2.state == "IDLE" \
				and p2._cur_key == "standing" and not p2.airborne:
			saw_stand = true
			print("TEST: thrown victim recovered to standing (t=", t, ")")
	if t == 950:
		stage1_ok = saw_grab_skill and saw_grabbed and saw_stand \
				and p1.hp >= p1.max_hp and not p2.ko
		print("THROW RESULT: grab=", saw_grab_skill, " grabbed=", saw_grabbed,
				" stand=", saw_stand, " p1.hp=", p1.hp, " p2.hp=", p2.hp,
				" p2.ko=", p2.ko)
		# stage 2: FM2K throw break — the victim taps E inside the connect
		# window and the toss never happens
		p2.manual_input = true
		p2.hp = p2.max_hp
		p1.pos.x = p2.pos.x - 33.0
	if t == 952:
		p1.ibuf.set_axis(InputBuffer.M_RIGHT)
		p1.ibuf.press(InputBuffer.B_E)
	if t == 954:
		p1.ibuf.set_axis(0)
	if t >= 950 and not b_connect and p2.break_t > 0:
		b_connect = true
		print("TEST: grab connect (t=", t, ") break window armed; tapping E")
		p2.ibuf.press(InputBuffer.B_E)
	if t >= 950 and b_connect and not b_broken and p2.state == "HIT":
		var sk2: Dictionary = p2.skill_by_index.get(p2.skill_idx, {})
		if String(sk2.get("n", "")).begins_with("Grab Bro"):
			b_broken = true
			print("TEST: victim 'Grab Broken' escape (t=", t, ")")
	if t >= 950 and b_connect and not b_freed and p1.state == "IDLE" \
			and p1._cur_key == "standing":
		b_freed = true
	if t == 1300:
		var hp_same := p2.hp == p2.max_hp
		var stand_again := p2.state == "IDLE" and p2._cur_key == "standing" \
				and not p2.airborne
		print("THROW-BRK RESULT: connect=", b_connect, " broken=", b_broken,
				" freed=", b_freed, " no_dmg=", hp_same, " stand=", stand_again,
				" p2.ko=", p2.ko)
		if stage1_ok and b_connect and b_broken and b_freed and hp_same \
				and stand_again and not p2.ko:
			print("THROW-TEST-PASS")
		else:
			print("THROW-TEST-FAIL")
		get_tree().quit()
