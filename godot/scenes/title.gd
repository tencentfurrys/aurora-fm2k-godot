extends Node2D
## Title/boot screen. Authentic KGT hex backdrop (img 2000) and K.O. plaque
## (img 22); Enter opens the character select, Esc quits.

var _blink: Label
var _t := 0.0

func _ready() -> void:
	# dev quick-jump: --scene=select jumps straight past the title
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			var s := a.substr(8)
			if s == "select" or s == "main":
				get_tree().change_scene_to_file("res://scenes/%s.tscn" % s)
				return

	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)

	_rect(layer, Vector2(0, 0), Vector2(320, 240), Color(0.02, 0.02, 0.04))

	# the authentic FM2K title screen (compiled from Title.json's art bank)
	var tex := Data.tex("assets/title/img/0000.png")
	if tex != null:
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.centered = false
		sp.scale = Vector2(0.5, 0.5)
		layer.add_child(sp)

	_blink = _label(layer, "press ENTER", Vector2(0, 206), 12, Color(1, 1, 1), Vector2(320, 18))
	_blink.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(layer, "FM2K -> Godot bridge   |   v0.9", Vector2(6, 228), 7, Color(0.42, 0.46, 0.54), Vector2(320, 10))

func _process(delta: float) -> void:
	_t += delta
	if _blink != null:
		_blink.modulate.a = 0.55 + 0.45 * sin(_t * 3.0)
	if Input.is_action_just_pressed("ui_accept"):
		get_tree().change_scene_to_file("res://scenes/select.tscn")
	elif Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()

func _input(event: InputEvent) -> void:
	# touch/mouse tap advances too (mobile APK + mouse emulation)
	var t := event as InputEventScreenTouch
	if t != null and t.pressed:
		get_tree().change_scene_to_file("res://scenes/select.tscn")

# ---------------------------------------------------------------- helpers
func _rect(layer: CanvasLayer, pos: Vector2, size: Vector2, col: Color) -> void:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = col
	layer.add_child(r)

func _label(layer: CanvasLayer, txt: String, pos: Vector2, fsize: int, col: Color, size: Vector2) -> Label:
	var l := Label.new()
	l.text = txt
	l.position = pos
	l.size = size
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	layer.add_child(l)
	return l
