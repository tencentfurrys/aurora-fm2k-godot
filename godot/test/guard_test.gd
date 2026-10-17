extends Node2D
## Headless guard regression. Flow under test: the victim holding back
## (FM2K guard) turns an attack connect into the authored guard junction
## (Guard WK Standin / Block Spark), takes only chip damage, freezes for the
## shorter guard hitstop, and recovers to standing.

const FIGHTER := preload("res://scripts/fighter.gd")

var t := 0
var p1: Fighter
var p2: Fighter
var saw_guard := false
var saw_stiff := false
var guard_hp := -1.0

func _ready() -> void:
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

func _physics_process(_d: float) -> void:
	t += 1
	if t == 40:
		print("TEST: distance before attack = ", absf(p2.pos.x - p1.pos.x))
		p2.manual_input = true
	if t == 42:
		# P2 faces left (toward P1): guard = holding away = screen right
		p2.ibuf.set_axis(InputBuffer.M_RIGHT)
	if t == 46:
		p1.manual_input = true
		p1.ibuf.press(InputBuffer.B_A)
	if t == 150 and not saw_guard:
		print("TEST: guard not observed yet, retrying point blank")
		p1.pos.x = p2.pos.x - 50.0
		p1.ibuf.press(InputBuffer.B_A)
	if t > 46 and t <= 500:
		if not saw_guard and p2.state == "HIT":
			var sk: Dictionary = p2.skill_by_index.get(p2.skill_idx, {})
			if String(sk.get("n", "")).begins_with("Guard"):
				saw_guard = true
				guard_hp = p2.hp
				print("TEST: victim guarding (t=", t, ") reaction='", sk.get("n"),
						"' hp=", p2.hp, " p1.stiff=", p1.stiff_t, " p2.stiff=", p2.stiff_t)
				# hitstop on both, guard freezes shorter
				if p1.stiff_t > 0 and p1.stiff_t <= 6 and p2.stiff_t > 0 \
						and p2.stiff_t <= 6:
					saw_stiff = true
		elif saw_guard and p2.hp != guard_hp:
			guard_hp = p2.hp          # guard gethit has active frames; keep last
	if t == 600:
		var loss := p2.max_hp - p2.hp
		# unguarded weak A = 56 dmg (FA pw 7 x 8); guard chip = ~20% -> ~11
		print("GUARD RESULT: saw_guard=", saw_guard, " saw_stiff=", saw_stiff,
				" chip_loss=", lossf(loss))
		if saw_guard and saw_stiff and loss > 3.0 and loss < 30.0 and p1.hp >= p1.max_hp \
				and not p2.ko:
			print("GUARD-TEST-PASS")
		else:
			print("GUARD-TEST-FAIL")
		get_tree().quit()

func lossf(v: float) -> float:
	return snappedf(v, 0.1)
