extends Node2D
## Virtual FM2K touch overlay: left d-pad stick + the five attack buttons
## (A B C D E) in their arcade arc, feeding the same InputBuffer a keyboard
## uses - raw 8-way axis via set_axis(InputBuffer.analog(...)) plus press /
## release edges. Built for the mobile APK target; on desktop it lights up
## when the project setting emulates touches from the mouse (or F3 forces it).
##
## Public feed_* entry points are the touch handlers; headless tests call
## them directly for deterministic coverage.

const DPAD_AT := Vector2(46, 182)
const DPAD_R := 30.0
const BTN_R := 13.0

var buf: Variant = null                 # fighter input buffer (main assigns p1.ibuf)
var btns := {}                          # letter -> {pos, mask}
var _stick_idx := -1                    # active d-pad touch index
var _stick_vec := Vector2.ZERO
var _btn_idx := {}                      # touch index -> letter
var _btn_down := {}                     # letter -> held

func _ready() -> void:
	btns = {
		"A": {"pos": Vector2(240, 150), "mask": InputBuffer.B_A},
		"B": {"pos": Vector2(268, 143), "mask": InputBuffer.B_B},
		"C": {"pos": Vector2(293, 152), "mask": InputBuffer.B_C},
		"D": {"pos": Vector2(252, 174), "mask": InputBuffer.B_D},
		"E": {"pos": Vector2(279, 168), "mask": InputBuffer.B_E},
	}
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			feed_down(t.index, t.position)
		else:
			feed_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_idx:
			feed_stick_to(d.position)

# ------------------------------------------------------------------ feeds
func feed_down(idx: int, pos: Vector2) -> void:
	if _stick_idx == -1 and pos.distance_to(DPAD_AT) <= DPAD_R + 8.0:
		_stick_idx = idx
		feed_stick_to(pos)
		queue_redraw()
		return
	for k in btns:
		if pos.distance_to(btns[k]["pos"]) <= BTN_R + 4.0:
			_btn_idx[idx] = k
			_btn_down[k] = true
			if buf != null:
				buf.press(int(btns[k]["mask"]))
			queue_redraw()
			return

func feed_up(idx: int) -> void:
	if idx == _stick_idx:
		_stick_idx = -1
		_stick_vec = Vector2.ZERO
		if buf != null:
			buf.set_axis(0)
		queue_redraw()
		return
	if _btn_idx.has(idx):
		var k: String = _btn_idx[idx]
		_btn_idx.erase(idx)
		_btn_down[k] = false
		if buf != null:
			buf.release(int(btns[k]["mask"]))
		queue_redraw()

func feed_stick_to(pos: Vector2) -> void:
	_stick_vec = (pos - DPAD_AT) / DPAD_R
	if buf != null:
		buf.set_axis(InputBuffer.analog(_stick_vec.x, _stick_vec.y))
	queue_redraw()

func pressed_mask() -> int:
	var m := 0
	for k in btns:
		if _btn_down.get(k, false):
			m |= int(btns[k]["mask"])
	return m

# ------------------------------------------------------------------ draw
func _draw() -> void:
	draw_circle(DPAD_AT, DPAD_R, Color(1, 1, 1, 0.10))
	draw_circle(DPAD_AT, DPAD_R, Color(1, 1, 1, 0.25), false, 1.0, true)
	# 8-way direction ticks
	var m := InputBuffer
	var marks := [Vector2(0, -1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1),
			Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(-1, -1)]
	for v in marks:
		var p: Vector2 = DPAD_AT + Vector2(v) * (DPAD_R * 0.72)
		draw_circle(p, 2.5, Color(1, 1, 1, 0.22))
	if _stick_idx != -1 and _stick_vec != Vector2.ZERO:
		var s: Vector2 = DPAD_AT + _stick_vec.limit_length(1.0) * DPAD_R * 0.6
		draw_circle(s, 9.0, Color(0.4, 0.9, 1.0, 0.45))
	else:
		draw_circle(DPAD_AT, 9.0, Color(1, 1, 1, 0.16))

	for k in btns:
		var pos: Vector2 = btns[k]["pos"]
		var down: bool = _btn_down.get(k, false)
		var col := Color(0.4, 0.9, 1.0, 0.4) if down else Color(1, 1, 1, 0.14)
		draw_circle(pos, BTN_R, col)
		draw_circle(pos, BTN_R, Color(1, 1, 1, 0.3), false, 1.0, true)
		var f: Font = ThemeDB.fallback_font
		draw_string(f, pos + Vector2(-BTN_R, 4.0), k,
				HORIZONTAL_ALIGNMENT_CENTER, BTN_R * 2.0, 9, Color(1, 1, 1, 0.55))
