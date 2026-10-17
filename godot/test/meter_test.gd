extends Node2D
## Headless meter regression. The authored super commands are gated by the
## FM2K spirit gauge (settings.meter = 160 on Applejack): with no meter a
## "Summer Rambo (Level 1)" motion + C must NOT launch its super (falls
## through to the basic), with 1/3 gauge it must launch skill #237 and
## spend the level cost, and the Level 3 super stays out of reach.

const FIGHTER := preload("res://scripts/fighter.gd")

var t := 0
var p1: Fighter
var p2: Fighter
var saw_super_block := true      # phase A: never launches #237 at meter 0
var saw_storm_block := true      # phase C: never launches #244 below full
var saw_super := false
var meter_after := -1.0

func _ready() -> void:
	p1 = FIGHTER.new()
	add_child(p1)
	p1.setup("Applejack", 0)
	p2 = FIGHTER.new()
	add_child(p2)
	p2.setup("Rainbow Dash", 1)
	p2.pos.x = 400.0                 # far away: nothing connects
	p1.opp = p2
	p2.opp = p1
	p2.ai = false

func _seq(tick: int) -> void:
	# authored "Summer Rambo (Level 1)" steps: 4(down) 13(comp) 6(left) 13 2(fwd)+C
	# (facing right: down -> right -> left -> down -> right, C on the arrival)
	if tick == 46 or tick == 250:
		p1.ibuf.set_axis(InputBuffer.M_DOWN)
	if tick == 52 or tick == 256:
		p1.ibuf.set_axis(InputBuffer.M_RIGHT)
	if tick == 58 or tick == 262:
		p1.ibuf.set_axis(InputBuffer.M_LEFT)
	if tick == 64 or tick == 268:
		p1.ibuf.set_axis(InputBuffer.M_DOWN)
	if tick == 72 or tick == 276:
		p1.ibuf.set_axis(InputBuffer.M_RIGHT)
		p1.ibuf.press(InputBuffer.B_C)
	# authored "Applebuck Storm (Level 3)" steps: 2 13 6 2 13 6 + C
	if tick == 350:
		p1.ibuf.set_axis(InputBuffer.M_RIGHT)
	if tick == 356:
		p1.ibuf.set_axis(InputBuffer.M_DOWN)
	if tick == 362:
		p1.ibuf.set_axis(InputBuffer.M_LEFT)
	if tick == 368:
		p1.ibuf.set_axis(InputBuffer.M_RIGHT)
	if tick == 374:
		p1.ibuf.set_axis(InputBuffer.M_DOWN)
	if tick == 380:
		p1.ibuf.set_axis(InputBuffer.M_LEFT)
	if tick == 386:
		p1.ibuf.press(InputBuffer.B_C)

func _physics_process(_d: float) -> void:
	t += 1
	_seq(t)
	if t == 40:
		p1.manual_input = true
		print("TEST: meter start = ", p1.meter, " max = ", p1.meter_max)
	if t == 220:
		# phase A verdict: Summer Rambo must not have launched (#237)
		saw_super_block = p1.skill_idx != 237
		print("TEST phase A: super_blocked=", saw_super_block, " skill=", p1.skill_idx)
	if t == 240:
		p1.meter = 60.0              # above the 1/3 gauge cost (54 on 160)
		print("TEST phase B: meter set to ", p1.meter)
	if t > 240 and t <= 500 and not saw_super and p1.skill_idx == 237:
		saw_super = true
		meter_after = p1.meter
		print("TEST: Summer Rambo launched (t=", t, ") meter after=", meter_after)
	if t == 420:
		# phase C verdict: Applebuck Storm (#244) must be unreachable below full
		saw_storm_block = p1.skill_idx != 244
		print("TEST phase C: storm_blocked=", saw_storm_block, " skill=", p1.skill_idx)
	if t == 520:
		print("METER RESULT: blockA=", saw_super_block, " superB=", saw_super,
				" meter_after=", meter_after, " blockC=", saw_storm_block)
		if saw_super_block and saw_storm_block and saw_super \
				and meter_after >= 0.0 and meter_after < 60.0:
			print("METER-TEST-PASS")
		else:
			print("METER-TEST-FAIL")
		get_tree().quit()
