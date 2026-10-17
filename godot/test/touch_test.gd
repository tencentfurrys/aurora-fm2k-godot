extends Node2D
## Headless regression for the virtual FM2K touch overlay: the d-pad stick
## resolves the 8-way axis through InputBuffer.analog (with its deadzone),
## the five buttons feed press/release edges, and two fingers coexist.

const DPAD_AT := Vector2(46, 182)

var a_press := false
var a_release := false
var stick_r := false
var stick_diag := false
var dead_ok := false
var multitouch := false
var c_release := false

func _ready() -> void:
	Data.reset_for_tests()
	var buf := InputBuffer.new()
	var tc: Variant = load("res://scripts/touch_controls.gd").new()
	tc.buf = buf
	add_child(tc)

	# 1) A press -> edge; release -> held clear
	tc.feed_down(1, Vector2(241, 151))
	buf.tick()
	a_press = buf.just_pressed(InputBuffer.B_A)
	tc.feed_up(1)
	buf.tick()
	a_release = not buf.held(InputBuffer.B_A) and not buf.just_pressed(InputBuffer.B_A)

	# 2) stick right
	tc.feed_down(2, DPAD_AT)
	tc.feed_stick_to(DPAD_AT + Vector2(25, 0))
	buf.tick()
	stick_r = buf.axis() == InputBuffer.M_RIGHT
	tc.feed_up(2)
	buf.tick()

	# 3) deadzone inside the stick ring
	tc.feed_down(3, DPAD_AT)
	tc.feed_stick_to(DPAD_AT + Vector2(5, 3))
	buf.tick()
	dead_ok = buf.axis() == 0
	tc.feed_up(3)
	buf.tick()

	# 4) diagonal down-right
	tc.feed_down(4, DPAD_AT)
	tc.feed_stick_to(DPAD_AT + Vector2(26, 26))
	buf.tick()
	stick_diag = buf.axis() == (InputBuffer.M_RIGHT | InputBuffer.M_DOWN)
	tc.feed_up(4)
	buf.tick()

	# 5) two fingers: d-pad right + C press in the same tick
	tc.feed_down(5, DPAD_AT + Vector2(27, 0))
	tc.feed_down(6, Vector2(293, 152))
	buf.tick()
	multitouch = buf.axis() == InputBuffer.M_RIGHT \
			and buf.just_pressed(InputBuffer.B_C)
	tc.feed_up(6)
	buf.tick()
	c_release = not buf.held(InputBuffer.B_C)
	tc.feed_up(5)

	var ok := a_press and a_release and stick_r and stick_diag\
			and dead_ok and multitouch and c_release
	print("TOUCH RESULT: a=%s a_release=%s right=%s diag=%s deadzone=%s multitouch=%s c_release=%s" % [
		a_press, a_release, stick_r, stick_diag, dead_ok, multitouch, c_release])
	print("TOUCH-TEST-PASS" if ok else "TOUCH-TEST-FAIL")
	get_tree().quit()
