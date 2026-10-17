extends Node2D
## Headless combat regression: hit connect -> junction gethit reaction ->
## KO. Prints state so failures are diagnosable from the log.

const FIGHTER := preload("res://scripts/fighter.gd")

var t := 0
var p1: Fighter
var p2: Fighter
var saw_reaction := false
var reaction_skill := ""

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

func _physics_process(_d: float) -> void:
	t += 1
	if t == 40:
		print("TEST: distance before attack = ", absf(p2.pos.x - p1.pos.x))
		p1.manual_input = true
		p1.ibuf.press(InputBuffer.B_A)
		print("TEST: weak press buffered")
	if t >= 42 and t <= 80 and not saw_reaction:
		if p2.state == "HIT":
			saw_reaction = true
			var sk: Dictionary = p2.skill_by_index.get(p2.skill_idx, {})
			reaction_skill = String(sk.get("n", "?"))
	if t == 140:
		print("TEST RESULT: p1.hp=", p1.hp, " p2.hp=", p2.hp, " p2.state=", p2.state,
				" dist=", absf(p2.pos.x - p1.pos.x))
		print("TEST reaction skill: '", reaction_skill, "'")
		if p2.hp >= p2.max_hp or not saw_reaction:
			print("HIT-TEST-FAIL")
			get_tree().quit()
			return
		print("HIT-TEST-PASS")
		p2.hp = 10.0   # next hit must KO
	if t == 168:
		p1.pos.x = p2.pos.x - 65.0   # walk up again (knockback left the whiff range)
	if t == 170:
		p1.ibuf.press(InputBuffer.B_A)
	if t == 260:
		print("KO TEST: p2.hp=", p2.hp, " ko=", p2.ko, " state=", p2.state, " dist=", absf(p2.pos.x - p1.pos.x))
		if p2.ko and p2.hp == 0.0:
			print("KO-TEST-PASS")
		else:
			print("KO-TEST-FAIL")
		get_tree().quit()
