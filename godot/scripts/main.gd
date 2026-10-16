extends Node2D
## Main scene: loads compiled data, spawns two FM2K-driven fighters on a
## compiled stage, and shows life bars + control hints.

const FIGHTER := preload("res://scripts/fighter.gd")

var p1: Fighter
var p2: Fighter
var _bar1: ColorRect
var _bar2: ColorRect
var _ko_label: Label

func _ready() -> void:
	_register_inputs()

	var man: Variant = Data.load_json("res://data/manifest.json")
	var chars: Array = (man.get("characters") if man != null else []) as Array
	var stages: Array = (man.get("stages") if man != null else []) as Array
	var char_a: String = String(chars[0]) if chars.size() > 0 else "Applejack"
	var char_b: String = String(chars[1]) if chars.size() > 1 else "Rainbow Dash"
	var stage_name: String = String(stages[0]) if stages.size() > 0 else "Training Stage"

	_build_stage(stage_name)

	p1 = FIGHTER.new()
	add_child(p1)
	p1.setup(String(char_a), 0)
	p1.pos = Vector2(110, 0)

	p2 = FIGHTER.new()
	add_child(p2)
	p2.setup(String(char_b), 1)
	p2.pos = Vector2(210, 0)

	p1.opp = p2
	p2.opp = p1
	p2.ai = true                      # demo brain walks & attacks on its own

	_build_hud(stage_name)

# --------------------------------------------------------------------- stage
func _build_stage(stage_name: String) -> void:
	var slug := Fighter._slug(stage_name)
	var st: Variant = Data.load_json("res://data/stages/%s.json" % slug)
	if st == null:
		return
	var chosen: Dictionary = {}
	for im in st.get("images", []):
		if int(im["w"]) > 0 and int(im["h"]) > 0:
			chosen = im
			break
	if chosen.is_empty():
		return
	var t := Data.tex(String(chosen["file"]))
	if t == null:
		return
	var bg := Sprite2D.new()
	bg.texture = t
	bg.centered = true
	bg.position = Vector2(160, 120)
	bg.z_index = 0
	bg.scale = Vector2(320.0 / float(chosen["w"]), 240.0 / float(chosen["h"]))
	add_child(bg)

# ----------------------------------------------------------------------- hud
func _build_hud(stage_name: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.55)
	back.position = Vector2(0, 0)
	back.size = Vector2(320, 16)
	layer.add_child(back)

	_bar1 = _mk_bar(layer, Vector2(4, 3), Vector2(100, 10), Color(0.2, 0.8, 0.3))
	_bar2 = _mk_bar(layer, Vector2(216, 3), Vector2(100, 10), Color(0.85, 0.7, 0.2))

	var lbl := Label.new()
	lbl.text = "FM2K -> Godot  |  %s vs %s  |  %s" % [p1.data.get("name", "?"), p2.data.get("name", "?"), Fighter._slug(stage_name).replace("_", " ")]
	lbl.position = Vector2(4, 222)
	lbl.add_theme_font_size_override("font_size", 8)
	layer.add_child(lbl)

	_ko_label = Label.new()
	_ko_label.text = "K.O.  —  press R"
	_ko_label.position = Vector2(120, 110)
	_ko_label.visible = false
	_ko_label.add_theme_font_size_override("font_size", 16)
	layer.add_child(_ko_label)

func _mk_bar(layer: CanvasLayer, pos: Vector2, size: Vector2, col: Color) -> ColorRect:
	var back := ColorRect.new()
	back.position = pos
	back.size = size
	back.color = Color(0.1, 0.1, 0.12)
	layer.add_child(back)
	var fill := ColorRect.new()
	fill.position = pos + Vector2(1, 1)
	fill.size = size - Vector2(2, 2)
	fill.color = col
	layer.add_child(fill)
	return fill

func _process(_delta: float) -> void:
	if _bar1 == null or p1 == null:
		return
	var r1 := p1.hp / maxf(p1.max_hp, 1.0)
	var r2 := p2.hp / maxf(p2.max_hp, 1.0)
	_bar1.size.x = 98.0 * r1
	_bar2.size.x = 98.0 * r2
	_ko_label.visible = p1.ko or p2.ko
	if Input.is_action_just_pressed("dbg_boxes"):
		Data.show_boxes = not Data.show_boxes
	if (p1.ko or p2.ko) and Input.is_action_just_pressed("reset_round"):
		_reset_round()

func _reset_round() -> void:
	for f in [p1, p2]:
		f.ko = false
		f.hp = f.max_hp
		f.stun_t = 0
		f.state = "IDLE"
		f.play_builtin("standing", true)
	p1.pos = Vector2(110, 0)
	p2.pos = Vector2(210, 0)

# ---------------------------------------------------------------- inputs
func _register_inputs() -> void:
	var map := {
		"p1_left": [KEY_A], "p1_right": [KEY_D], "p1_up": [KEY_W], "p1_down": [KEY_S],
		"p1_a": [KEY_J], "p1_b": [KEY_K], "p1_c": [KEY_L], "p1_d": [KEY_I], "p1_e": [KEY_U],
		"p2_left": [KEY_LEFT], "p2_right": [KEY_RIGHT], "p2_up": [KEY_UP],
		"p2_down": [KEY_DOWN], "p2_a": [KEY_KP_1], "p2_b": [KEY_KP_2],
		"p2_c": [KEY_KP_3], "p2_d": [KEY_KP_4], "p2_e": [KEY_KP_5],
		"dbg_boxes": [KEY_F1],
		"reset_round": [KEY_R],
	}
	for action in map:
		_add_action(action, map[action])

func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
