extends Node2D
## Headless knockdown/wake-up regression. Flow under test: a command-launched
## move whose junction is one of the FM2K down states (Crouching Heavy ->
## junction "Knocked Down Light") must NOT snap back to standing like a plain
## hitstun; the victim plays the knockdown gethit skill, then the authored
## wake-up skill ("Fall Down Get Up"), then stands. Also sanity-checks that
## every fighter in the compiled roster has an authored wake-up skill.

const FIGHTER := preload("res://scripts/fighter.gd")

var t := 0
var p1: Fighter
var p2: Fighter
var saw_kd := false
var saw_getup := false
var saw_stand := false

func _ready() -> void:
	# 1) every fighter that authors knockdown states has an authored wake-up
	var m: Dictionary = Data.load_json("res://data/manifest.json")
	var missing: Array[String] = []
	var checked := 0
	for c in m.get("characters", []):
		var f := FIGHTER.new()
		add_child(f)
		f.setup(String(c), 0)
		var has_down := false
		for sk2 in f.data.get("skills", []):
			var n2 := String(sk2.get("n", "")).to_lower()
			if n2.begins_with("knocked down") or n2.begins_with("knockdown"):
				has_down = true
				break
		if has_down:
			checked += 1
			if f.wake_skill < 0:
				missing.append(String(c))
		f.queue_free()
	if not missing.is_empty():
		print("KD-TEST-FAIL: no wake-up skill for: ", missing)
		get_tree().quit()
		return
	print("TEST: wake-up skill found for all ", checked, " fighters with down states")
	# 2) live knockdown -> wake-up flow
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
		p1.manual_input = true
	if t == 44:
		p1.ibuf.set_axis(InputBuffer.M_DOWN)   # crouched stance for the Heavy ls ref
	if t == 46:
		p1.ibuf.press(InputBuffer.B_C)         # Heavy -> crouched skill (KD junction)
	if t == 150 and not saw_kd:
		# retry from point blank if the crouched heavy whiffed at 65px
		print("TEST: knockdown not observed yet, retrying point blank")
		p1.pos.x = p2.pos.x - 55.0
		p1.ibuf.press(InputBuffer.B_C)
	if t > 44 and t <= 500:
		if not saw_kd and p2.state == "HIT":
			var sk: Dictionary = p2.skill_by_index.get(p2.skill_idx, {})
			if String(sk.get("n", "")).begins_with("Knocked Down"):
				saw_kd = true
				print("TEST: victim knocked down (t=", t, ") reaction='", sk.get("n"), "'")
		elif saw_kd and not saw_getup and p2.state == "ACT":
			var sk2: Dictionary = p2.skill_by_index.get(p2.skill_idx, {})
			if String(sk2.get("n", "")) == "Fall Down Get Up":
				saw_getup = true
				print("TEST: victim entering wake-up (t=", t, ")")
		elif saw_getup and not saw_stand and p2.state == "IDLE" \
				and p2._cur_key == "standing" and not p2.airborne:
			saw_stand = true
			print("TEST: victim back to standing (t=", t, ")")
			# shorten the log: jump to verdict once the whole flow is seen
			_verdict()
			return
	if t == 600:
		_verdict()

func _verdict() -> void:
	print("KD-RESULT: saw_kd=", saw_kd, " saw_getup=", saw_getup, " saw_stand=", saw_stand,
			" p2.state=", p2.state, " p2.hp=", p2.hp)
	if saw_kd and saw_getup and saw_stand:
		print("KD-TEST-PASS")
	else:
		var sk: Dictionary = p2.skill_by_index.get(p2.skill_idx, {})
		print("KD-TEST-FAIL: p2 skill='", String(sk.get("n", "-")), "'")
	get_tree().quit()
