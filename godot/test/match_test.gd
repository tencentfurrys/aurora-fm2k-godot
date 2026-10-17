extends Node2D
## Headless match-flow regression: best-of-3 rounds through the real main
## fight scene with the KGT announcer chain — Round card -> Fight -> KO card
## chain -> round reset -> Round 2 -> KO -> match end with the winner's
## authored victory pose and the 1P Wins card.

const MAIN := preload("res://scripts/main.gd")

var t := 0
var m: Node2D
var fed_1 := false
var fed_2 := false
var saw_fight := false
var saw_reset := false
var saw_ko := false
var saw_end := false
var victory_ok := false
var pips_ok := false
var cont_boot := false
var cont_watch := false
var saw_cont := false
var cont_num_seen := -1

func _ready() -> void:
	Data.reset_for_tests()
	MAIN.p1_name = "Applejack"
	MAIN.p2_name = "Rainbow Dash"
	MAIN.stage_name = "Training Stage"
	MAIN.demo_ai = false
	var scene: PackedScene = load("res://scenes/main.tscn")
	m = scene.instantiate()
	add_child(m)

func _physics_process(_d: float) -> void:
	t += 1
	if m == null or m.p1 == null or m.p2 == null:
		return

	if m._phase == "fight":
		saw_fight = true
		# round 1 kill
		if m._round == 1 and not fed_1:
			fed_1 = true
			m.p2.hp = 1.0
			m.p1.pos.x = m.p2.pos.x - 55.0
			m.p1.ibuf.press(InputBuffer.B_A)
		# round 2 kill (after the reset re-positions both fighters)
		if m._round == 2 and fed_1 and m.card_history.has("Round 2"):
			if m.p2.hp >= m.p2.max_hp and m.p2.pos == Vector2(210, 0):
				saw_reset = true
			if not fed_2 and saw_reset:
				fed_2 = true
				m.p2.hp = 1.0
				m.p1.pos.x = m.p2.pos.x - 55.0
				m.p1.ibuf.press(InputBuffer.B_A)

	if m._phase == "ko":
		saw_ko = true

	if m._phase == "end":
		saw_end = true
		if not victory_ok:
			var sk: Dictionary = m.p1.skill_by_index.get(m.p1.skill_idx, {})
			if String(sk.get("n", "")).begins_with("Victory"):
				victory_ok = true
		if int(m._wins[0]) == 2 and int(m._wins[1]) == 0:
			pips_ok = true

	if t == 2400:
		var cards: Array[String] = m.card_history
		var ok := saw_fight and saw_ko and saw_end and saw_reset \
				and victory_ok and pips_ok \
				and cards.has("Round 1") and cards.has("Fight") \
				and cards.has("Knock Out") and cards.has("Round 2") \
				and cards.has("1P Wins")
		print("MATCH RESULT: fight=%s ko=%s reset=%s end=%s victory=%s pips=%s cards=%s" % [
			saw_fight, saw_ko, saw_reset, saw_end, victory_ok, pips_ok, ", ".join(cards)])
		print("MATCH-TEST-PASS" if ok else "MATCH-TEST-FAIL")
		# stage 2: FM2K continue screen (demo-AI match the human lost). The
		# transition is process-clocked, so capture it on first sight.
		m.demo_ai = true
		m._winner = 1
		m._phase = "end"
		m._end_t = 0
		cont_watch = true
	if cont_watch and not saw_cont and String(m._phase) == "continue" \
			and m._cont_layer != null:
		saw_cont = true
		cont_num_seen = int(m._cont_num)
		m._do_continue(true)
	if t == 2560:
		var rematch: bool = saw_cont and String(m._phase) == "intro" \
				and int(m._wins[0]) == 0 and int(m._wins[1]) == 0 \
				and int(m._round) == 1
		print("CONTINUE RESULT: boot=%s count=%s rematch=%s" % [
			saw_cont, cont_num_seen, rematch])
		print("CONTINUE-TEST-PASS" if saw_cont and rematch else "CONTINUE-TEST-FAIL")
		get_tree().quit()
