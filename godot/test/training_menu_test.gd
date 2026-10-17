extends Node2D
## Headless test for the v0.9 FM2K training/pause menu: page/cursor build,
## authored toggle rows flipping persisted values (debug button = the FD box
## view, auto teching's engine effect, auto healing), the command-list card
## swap, and the exit-to-title request recorded under Data.suppress_exit.

var t := 0          # deterministic physics tick counter (single increment)
var v: Node2D
var begun := false
var open_ok := false
var nav_ok := false
var card_ok := false
var back_ok := false
var boxes_ok := false
var save_ok := false
var tech_ok := false
var heal_ok := false
var exit_ok := false

func _ready() -> void:
	Data.reset_for_tests()
	Data.suppress_exit = true
	# deterministic toggles: wipe any persisted state from earlier runs
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists("aurora_settings.cfg"):
		dir.remove("aurora_settings.cfg")
	Data.show_boxes = false
	Data.auto_tech = false
	Data.auto_heal = false
	Data.lo_fi = false
	var sc: PackedScene = load("res://scenes/main.tscn")
	v = sc.instantiate()
	add_child(v)

func _physics_process(_d: float) -> void:
	if v == null:
		return
	if v._phase != "fight":
		# the AI stays off for determinism; buffers are fed by this test
		v.p1.manual_input = true
		v.p2.manual_input = true
		return
	t += 1
	if not begun:
		if t < 5:
			return
		begun = true
		v.p1.manual_input = true
		v._toggle_pause(true)
		open_ok = v._paused and v._pgs.size() == 4 and v._pgs[0].visible \
				and v._cursor.visible and v._cursor.position.is_equal_approx(Vector2(40, 75))
		return
	if t > 200:
		print("TRAIN-MENU-FAIL-TIMEOUT page=", v._pause_page, " row=", v._pause_row)
		get_tree().quit()
		return
	match t:
		6: v.p1.ibuf.set_axis(InputBuffer.M_DOWN)
		8:
			v.p1.ibuf.set_axis(0)
			nav_ok = v._pause_row == 1 and v._cursor.position.is_equal_approx(Vector2(40, 110))
		12: v.p1.ibuf.press(InputBuffer.B_A)
		13: v.p1.ibuf.release(InputBuffer.B_A)
		15:
			# command list page opened, card art loaded
			card_ok = v._pause_page == 2 and v._menu_card != null and v._menu_card.texture != null
		18: v.p1.ibuf.set_axis(InputBuffer.M_LEFT)
		20:
			v.p1.ibuf.set_axis(0)
			card_ok = card_ok and v._card_pick == 1
		24: v.p1.ibuf.press(InputBuffer.B_B)
		25: v.p1.ibuf.release(InputBuffer.B_B)
		27:
			# menu reads the edge one committed snapshot late (parent order)
			back_ok = v._pause_page == 0
		28:
			v.p1.ibuf.press(InputBuffer.B_A)   # row0 -> training options page
		29:
			v.p1.ibuf.release(InputBuffer.B_A)
		31:
			boxes_ok = v._pause_page == 1
			if not boxes_ok:
				print("DBG t=31 page=", v._pause_page, " row=", v._pause_row,
						" boxes=", Data.show_boxes)
		34:
			v.p1.ibuf.press(InputBuffer.B_A)   # flip 'debug button:' unlocked
		35:
			v.p1.ibuf.release(InputBuffer.B_A)
		37:
			boxes_ok = boxes_ok and Data.show_boxes \
					and v._statuses.size() == 3 and v._statuses[0].texture != null
			save_ok = FileAccess.file_exists(Data.SETTINGS_PATH)
		40: v.p1.ibuf.set_axis(InputBuffer.M_DOWN)
		42: v.p1.ibuf.set_axis(0)
		46:
			v.p1.ibuf.press(InputBuffer.B_A)   # flip 'auto teching:' on
		47:
			v.p1.ibuf.release(InputBuffer.B_A)
		49:
			# engine check: a plain hit reaction pops out in 4 ticks when
			# auto teching is on, and rides the plain 24-tick stun when off
			v.p2.enter_reaction(0)
			var cap_ok: bool = v.p2.state == "HITSTUN" and v.p2.stun_t == 4
			Data.auto_tech = false
			v.p2.enter_reaction(0)
			var free_ok: bool = v.p2.state == "HITSTUN" and v.p2.stun_t == 24
			tech_ok = cap_ok and free_ok and not Data.auto_tech
		54: v.p1.ibuf.set_axis(InputBuffer.M_DOWN)
		56: v.p1.ibuf.set_axis(0)
		60:
			v.p1.ibuf.press(InputBuffer.B_A)   # flip 'auto healing:' on
		61:
			v.p1.ibuf.release(InputBuffer.B_A)
		63:
			heal_ok = Data.auto_heal
			v._toggle_pause(false)             # close the menu (undoing freeze)
			v.p2.state = "IDLE"
			v.p2.hp = 500.0
		65: heal_ok = heal_ok and v.p2.hp >= v.p2.max_hp
		68:
			# the real exit path: reopen the menu (page 0), then Esc
			v._toggle_pause(true)
		70:
			v._pause_esc()
			exit_ok = v._pause_exit and v._paused and v._pause_page == 0
			var all: bool = open_ok and nav_ok and card_ok and back_ok \
					and boxes_ok and save_ok and tech_ok and heal_ok and exit_ok
			print("TRAIN-MENU RESULT: open=%s nav=%s card=%s back=%s boxes=%s save=%s tech=%s heal=%s exit=%s" % [
				open_ok, nav_ok, card_ok, back_ok, boxes_ok, save_ok, tech_ok, heal_ok, exit_ok])
			print("TRAIN-MENU-PASS" if all else "TRAIN-MENU-FAIL")
			get_tree().quit()
