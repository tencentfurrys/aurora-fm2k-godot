class_name Fighter
extends Node2D
## FM2K-driven fighter. Plays compiled skill frame lists (anim frames, movement
## events, sound events) exactly like the FM2K runtime walks a skill block list.
##
## Coordinate system: pos.x = horizontal position in px; pos.y = vertical
## position where 0 == ground level and negative == up in the air (FM2K-style).
## Movement events from M blocks are interpreted as per-tick displacement in
## 1/100-px units (FM2K's internal fixed point).

const MOVE_SCALE := 0.01
const GROUND_Y := 200.0
const GROUND_TO_ANCHOR := 88.0   # empirically fitted: sprite canvas centers sit
                                 # 88px above the ground line (95.6% joint box/
                                 # sprite coverage on Applejack + Rainbow Dash)

signal landed

var data: Dictionary = {}
var img_by_id: Dictionary = {}
var snd_by_id: Dictionary = {}         # sound id -> file path
var skill_by_name: Dictionary = {}
var skill_by_index: Dictionary = {}
var ibuf: InputBuffer = InputBuffer.new()   # per-player input history
var builtin: Dictionary = {}
var input_prefix := "p1_"

var pos := Vector2.ZERO                # x along ground, y negative = airborne
var move := Vector2.ZERO               # px per tick (already scaled)
var grav := Vector2.ZERO               # additive per tick
var facing := 1                        # +1 faces right

var state := "IDLE"                    # IDLE | ACT | HITSTUN | KO
var skill_idx := -1
var loop_skill := false
var frame_pos := 0
var frame_t := 0
var skill_t := 0                       # ticks elapsed in the current skill
var airborne := false
var play_locked := false               # attack lock: no skill switch until end
var _cur_key := ""

var hp := 1000.0
var max_hp := 1000.0
var stun_t := 0                        # fallback hitstun ticks (no junction reaction)
const DMG_SCALE := 8.0                 # FA power -> HP (calibrated: WK ~11% of 515)
const STAND_FAR_DIST := 140.0          # command stand-far skill beyond this
var ko := false
var hit_done := false                  # one hit per attack instance
var box_slots := {}                    # FM2K FD slot n -> box dict
var fa_slots := {}                     # FM2K FA attack-force slot n -> event dict
var ai := false                        # P2 demo brain
var manual_input := false              # external owner feeds ibuf directly
var _ai_tick := 0

var opp: Fighter = null

var _spr: Sprite2D
var _audio: AudioStreamPlayer

func _ready() -> void:
	_spr = Sprite2D.new()
	_spr.centered = true
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_spr)
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	z_index = 1

func setup(char_name: String, side_side: int) -> void:
	var d: Variant = Data.load_json("res://data/characters/%s.json" % _slug(char_name))
	if d == null or d.is_empty():
		push_error("Fighter: no compiled data for %s" % char_name)
		return
	data = d
	img_by_id = Data.index_images(data.get("images", []))
	snd_by_id.clear()
	for s in data.get("sounds", []):
		snd_by_id[int(s["id"])] = String(s["file"])
	skill_by_name.clear()
	skill_by_index.clear()
	for sk in data.get("skills", []):
		skill_by_name[sk["n"]] = sk
		skill_by_index[int(sk["i"])] = sk
	builtin = data.get("builtin", {})
	# FM2K basic attacks (Weak/Mid/Heavy) are ordinary commands in the list,
	# so the single command matcher covers basics + specials uniformly.
	var settings: Dictionary = data.get("settings", {})
	max_hp = float(settings.get("life", 1000))
	hp = max_hp
	var prefix := "p" + ("1" if side_side == 0 else "2") + "_"
	input_prefix = prefix
	facing = 1 if side_side == 0 else -1
	play_builtin("standing")

static func _slug(name: String) -> String:
	var s := name.to_lower().strip_edges().replace(" ", "_")
	s = s.replace("'", "").replace(".", "").replace("-", "_")
	s = s.replace("(", "").replace(")", "")
	return s

# ------------------------------------------------------------------ runtime
func _physics_process(_delta: float) -> void:
	if data.is_empty():
		return
	_feed_buffer()
	ibuf.tick()
	if state == "IDLE":
		_poll_idle()
	elif state == "ACT":
		_poll_cancels()
	elif state == "HITSTUN":
		stun_t -= 1
		if stun_t <= 0:
			state = "IDLE"
			move = Vector2.ZERO
	_apply_physics()
	if state != "HITSTUN":
		_tick_anim()
	_update_sprite()
	if state == "KO":
		queue_redraw()
		return
	_combat_tick()
	queue_redraw()

# ------------------------------------------------------------------- inputs
## Gather this tick's raw input. The AI writes decision feeds exactly like a
## human player would, so every code path exercises the same buffer. With
## manual_input=true the owner (headless tests, and later the mobile touch
## overlay) pends state into ibuf itself between ticks.
func _feed_buffer() -> void:
	if ai:
		_ai_write()
		return
	if manual_input:
		return
	var m := 0
	if _axis("left"):
		m |= InputBuffer.M_LEFT
	if _axis("right"):
		m |= InputBuffer.M_RIGHT
	if _axis("down"):
		m |= InputBuffer.M_DOWN
	if _axis("up"):
		m |= InputBuffer.M_UP
	ibuf.set_axis(m)
	for p in [["a", InputBuffer.B_A], ["b", InputBuffer.B_B], ["c", InputBuffer.B_C],
			["d", InputBuffer.B_D], ["e", InputBuffer.B_E]]:
		var act := input_prefix + String(p[0])
		if not InputMap.has_action(act):
			continue
		if Input.is_action_just_pressed(act):
			ibuf.press(int(p[1]))
		elif not Input.is_action_pressed(act):
			ibuf.release(int(p[1]))

func _axis(action: String) -> bool:
	if not InputMap.has_action(input_prefix + action):
		return false
	return Input.is_action_pressed(input_prefix + action)

func _just(action: String) -> bool:
	if not InputMap.has_action(input_prefix + action):
		return false
	return Input.is_action_just_pressed(input_prefix + action)

## Movement from FM2K M blocks: pos += move each tick, move += grav each tick.
func _apply_physics() -> void:
	var affected: Vector2 = move
	var was_air := airborne
	move += grav
	pos.x += affected.x * facing
	pos.y += affected.y
	if pos.y >= 0.0 and was_air:
		pos.y = 0.0
		move = Vector2.ZERO
		grav = Vector2.ZERO
		airborne = false
		landed.emit()
		if state == "IDLE":
			play_builtin("standing")   # only idle chars snap to standing on land
	position = Vector2(pos.x, GROUND_Y + pos.y)

## Event pipeline: fire moves/sounds attached to the frame that begins this tick.
func _tick_anim() -> void:
	skill_t += 1
	if skill_idx < 0:
		return
	var sk: Dictionary = skill_by_index.get(skill_idx, {})
	if sk.is_empty():
		return
	var frames: Array = sk.get("frames", [])
	if frames.is_empty():
		return
	var fr: Dictionary = frames[frame_pos]
	if frame_t == 0:
		for mv in sk.get("moves", []):
			if int(mv["t"]) == frame_pos:
				_apply_move(mv)
		for snd in sk.get("sounds", []):
			if int(snd["t"]) == frame_pos:
				_play_sound(int(snd["s"]))
		for bx in sk.get("boxes", []):
			if int(bx["t"]) == frame_pos:
				box_slots[int(bx["n"])] = bx
		for fa in sk.get("farces", []):
			if int(fa["t"]) == frame_pos:
				fa_slots[int(fa["n"])] = fa
	frame_t += 1
	if int(fr.get("d", 1)) <= 0 or fr.get("hold") == 1:
		if state == "HIT":
			# reaction animation finished (incl. knockdown hold) -> wake up
			_end_hit()
		return
	if frame_t >= int(fr["d"]):
		frame_t = 0
		frame_pos += 1
		if frame_pos >= frames.size():
			if loop_skill:
				frame_pos = 0
			elif state == "HIT":
				_end_hit()
			else:
				frame_pos = frames.size() - 1
				if not airborne:
					state = "IDLE"
					move = Vector2.ZERO
					play_builtin("standing")

## Reaction ended: v0.2 wake-up proxy (real kd/wake-up flow is v0.3).
func _end_hit() -> void:
	state = "IDLE"
	move = Vector2.ZERO
	grav = Vector2.ZERO
	if not airborne:
		play_builtin("standing")

func _apply_move(mv: Dictionary) -> void:
	var dmx := float(mv["mx"]) * MOVE_SCALE
	var dmy := float(mv["my"]) * MOVE_SCALE
	var dgx := float(mv["gx"]) * MOVE_SCALE
	var dgy := float(mv["gy"]) * MOVE_SCALE
	if bool(mv["add"]):
		if dmx != 0.0 or dmy != 0.0:
			move += Vector2(dmx, dmy)
		if dgx != 0.0 or dgy != 0.0:
			grav += Vector2(dgx, dgy)
	else:
		move = Vector2(dmx, dmy)
		grav = Vector2(dgx, dgy)
	if bool(mv["sx"]) or bool(mv["sy"]):
		move = Vector2.ZERO if bool(mv["sx"]) and bool(mv["sy"]) else Vector2(0.0 if bool(mv["sx"]) else move.x, 0.0 if bool(mv["sy"]) else move.y)
	if bool(mv["sgx"]) or bool(mv["sgy"]):
		grav = Vector2(0.0 if bool(mv["sgx"]) else grav.x, 0.0 if bool(mv["sgy"]) else grav.y)

func _play_sound(sound_id: int) -> void:
	var snd_idx := {}
	for s in data.get("sounds", []):
		snd_idx[int(s["id"])] = s
	var meta: Dictionary = snd_idx.get(sound_id, {})
	if meta.is_empty():
		return
	var st := Data.wav(meta["file"])
	if st != null:
		_audio.stream = st
		_audio.play()

# --------------------------------------------------------------- state input
func _poll_idle() -> void:
	# 1) commands (authored list order = FM2K priority: supers/specials first,
	#    engine basics Weak/Mid/Heavy last as catch-alls)
	if _try_launch_command():
		return
	# 2) movement, resolved from the buffer's screen-space axis
	if airborne:
		play_builtin("falling", true)
		return
	var m := ibuf.axis()
	if (m & InputBuffer.M_DOWN) != 0:
		play_builtin("crouching", true)
		move = Vector2.ZERO
		return
	if (m & (InputBuffer.M_LEFT | InputBuffer.M_RIGHT)) != 0:
		var dir := 0
		if (m & InputBuffer.M_LEFT) != 0:
			dir -= 1
		if (m & InputBuffer.M_RIGHT) != 0:
			dir += 1
		play_builtin("forward" if dir == facing else "backward", true)
		return
	if (m & InputBuffer.M_UP) != 0:
		_start_jump()
		return
	play_builtin("standing", true)

## First matching command in authored order, launching its state-suitable
## skill: air / stand / stand-far / crouched (the command's four refs).
func _try_launch_command() -> bool:
	for cmd in data.get("commands", []):
		if not ibuf.match_command(cmd, facing):
			continue
		var ls: Dictionary = cmd.get("ls", {})
		var sidx := 0
		if airborne:
			sidx = int(ls.get("a", 0))
		elif (ibuf.axis() & InputBuffer.M_DOWN) != 0:
			sidx = int(ls.get("c", 0))
		elif int(ls.get("sf", 0)) != 0 and opp != null \
				and absf(opp.pos.x - pos.x) > STAND_FAR_DIST:
			sidx = int(ls.get("sf", 0))
		else:
			sidx = int(ls.get("s", 0))
		if sidx == 0 or not skill_by_index.has(sidx):
			continue                     # no skill for this state: next cmd
		if _start_skill_idx(sidx):
			ibuf.consume_edges()
			return true
	return false

## FM2K C-block cancels: while an attack is inside a cancel row's frame
## window (and the row's condition holds - connected for hits=true, always
## for uncond=true), the command set is live again: chains into other
## basics and buffered special commands can cancel the attack.
func _poll_cancels() -> void:
	if loop_skill:
		return
	var sk: Dictionary = skill_by_index.get(skill_idx, {})
	if sk.is_empty():
		return
	for c in sk.get("cancels", []):
		if skill_t < int(c.get("from", 0)) or skill_t > int(c.get("to", 0)):
			continue
		if bool(c.get("uncond", false)) or (bool(c.get("hits", false)) and hit_done):
			if _try_launch_command():
				return

## Demo brain for P2: writes decision feeds exactly like a human source.
func _ai_write() -> void:
	_ai_tick += 1
	if opp == null:
		ibuf.set_axis(0)
		return
	var dist := absf(opp.pos.x - pos.x)
	var m := 0
	if dist >= 60.0:
		m = InputBuffer.M_RIGHT if opp.pos.x > pos.x else InputBuffer.M_LEFT
		if _ai_tick % 233 > 222:
			m |= InputBuffer.M_UP        # occasional jump toward
	ibuf.set_axis(m)
	if _ai_tick % 34 == 0 and dist < 95.0 and randi() % 3 != 0:
		ibuf.press([InputBuffer.B_A, InputBuffer.B_B, InputBuffer.B_C][randi() % 3])

func _start_jump() -> void:
	if airborne:
		return
	if play_builtin("jumpUp", false):
		airborne = true

# ------------------------------------------------------------------- anims
## Enter a skill by builtin key; returns success. Looping builtins don't
## restart if the same one is already playing.
func play_builtin(key: String, loop: bool = false) -> bool:
	if key == _cur_key and loop_skill:
		return true
	var idx := int(builtin.get(key, -1))
	if idx < 0:
		return false
	var is_loop_kind := key in ["standing", "forward", "backward", "crouching", "falling"]
	var ok := _enter_skill(idx, loop or is_loop_kind)
	if ok:
		_cur_key = key
		if loop_skill and not ko:
			# idle loops stay responsive: keep the state machine in IDLE so
			# every tick still runs _poll_idle (input/commands stay live)
			state = "IDLE"
	return ok

func _start_skill_idx(idx: int) -> bool:
	var ok := _enter_skill(idx, false)
	if ok:
		_cur_key = ""
	return ok

func _enter_skill(idx: int, loop: bool) -> bool:
	if idx < 0 or not skill_by_index.has(idx):
		return false
	skill_idx = idx
	loop_skill = loop
	frame_pos = 0
	frame_t = 0
	skill_t = 0
	state = "ACT"
	move = Vector2.ZERO
	grav = Vector2.ZERO
	hit_done = false
	return true

func _update_sprite() -> void:
	if skill_idx < 0 or not skill_by_index.has(skill_idx):
		return
	var frames: Array = skill_by_index[skill_idx].get("frames", [])
	if frames.is_empty():
		return
	var fr: Dictionary = frames[frame_pos]
	var meta: Dictionary = img_by_id.get(int(fr["i"]), {})
	if meta.is_empty():
		_spr.visible = false
		return
	_spr.visible = true
	var t := Data.tex(String(meta["file"]))
	if t == null:
		_spr.visible = false
		return
	_spr.texture = t
	var flip_by_facing := facing == -1
	var flip_frame := bool(fr.get("fx", false))
	_spr.flip_h = flip_by_facing != flip_frame
	_spr.flip_v = bool(fr.get("fy", false))
	var mirrored_x := -float(fr["x"]) if facing == -1 else float(fr["x"])
	# canvas center sits GROUND_TO_ANCHOR above the ground line (node origin)
	_spr.position = Vector2(mirrored_x, float(fr["y"]) - GROUND_TO_ANCHOR)

# ------------------------------------------------------------------- combat
## FD slot rects. kind: "col" attack/solid, "dmg" hurt, "thr" throw.
## world=true returns rects in global screen space (node = ground point);
## world=false returns them local to the ground point (origin +y down).
## X is mirrored for facing == -1 (FM2K authors boxes facing-right).
func _slot_rects(kind: String, world: bool = true) -> Array[Rect2]:
	var base_y := position.y if world else 0.0
	var base_x := position.x if world else 0.0
	var mirror := facing == -1
	var out: Array[Rect2] = []
	for b in box_slots.values():
		if bool(b.get(kind, false)) and b["w"] > 0 and b["h"] > 0:
			var lx: float = (-float(b["x"]) - float(b["w"]) / 2) if mirror else (float(b["x"]) - float(b["w"]) / 2)
			out.append(Rect2(base_x + lx, base_y + float(b["y"]) - float(b["h"]),
					float(b["w"]), float(b["h"])))
	return out

func _combat_tick() -> void:
	if opp == null or ko:
		return
	# 1) bodies push apart when their solid boxes overlap (grounded only,
	#    never while an attack or hit reaction instance is running)
	if not airborne and not opp.airborne \
			and not _is_attack_skill() and not opp._is_attack_skill() \
			and state != "HIT" and opp.state != "HIT":
		for a in _slot_rects("col"):
			for b in opp._slot_rects("col"):
				if a.intersects(b):
					var ovl: float = minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
					if ovl > 0.0:
						var dir := signf(pos.x - opp.pos.x)
						if dir == 0.0:
							dir = 1.0 if facing > 0 else -1.0
						var half := ovl * 0.5
						pos.x += dir * half
						opp.pos.x -= dir * half
	# 2) attack connect, once per skill instance (FM2K: only command-launched
	#    attack skills run junctions; idle dmg boxes are pure hurt zones)
	if stun_t > 0 or hit_done or state == "KO" or opp.ko:
		return
	if not _is_attack_skill():
		return
	var opp_hurt: Array[Rect2] = opp._slot_rects("dmg")
	if opp_hurt.is_empty():
		return
	# FA attack-force area carries the power(); connect there first
	var zone := Rect2()
	var pw := -1
	for fa in fa_slots.values():
		if int(fa.get("pw", 0)) <= 0 or fa["w"] <= 0 or fa["h"] <= 0:
			continue
		for b in opp_hurt:
			var r := _local_rect_world(float(fa["x"]), float(fa["y"]), float(fa["w"]), float(fa["h"]))
			var z := r.intersection(b)
			if z.size.x > 0 and z.size.y > 0:
				zone = z
				pw = int(fa["pw"])
	# fallback: strike (dmg) boxes connect without a power area
	if pw < 0:
		for a in _slot_rects("dmg"):
			for b in opp_hurt:
				var z2 := a.intersection(b)
				if z2.size.x > 0 and z2.size.y > 0:
					zone = z2
					pw = -1
					_register_hit(zone.get_center(), opp, pw)
					return
		return
	_register_hit(zone.get_center(), opp, pw)

func _local_rect_world(cx: float, cy: float, bw: float, bh: float) -> Rect2:
	var mirror := facing == -1
	var lx: float = (-cx - bw / 2) if mirror else (cx - bw / 2)
	return Rect2(position.x + lx, position.y + cy - bh, bw, bh)

func _is_attack_skill() -> bool:
	# standing/walking/crouching slots are solid bodies; only skills entered as
	# attacks (via command binding) can connect
	if _cur_key != "":
		return false
	return state == "ACT" and not loop_skill

## FM2K R block: junction index per victim stance.
func _junction_ref() -> Dictionary:
	var sk: Dictionary = skill_by_index.get(skill_idx, {})
	var react: Dictionary = sk.get("reactions", {})
	if react.is_empty():
		return {}
	match opp._stance():
		"crouch":
			return {"j": int(react.get("hc", 0))}
		"air":
			return {"j": int(react.get("ha", 0))}
	return {"j": int(react.get("hs", 0))}

func _stance() -> String:
	if airborne:
		return "air"
	var crouches := ["crouching", "midCrouch", "crouchAdvance", "crouchRetreat"]
	if crouches.has(_cur_key):
		return "crouch"
	return "stand"

## Victim's junction table entry (gethit skill + spark skill indices).
func junction_entry(junction_idx: int) -> Dictionary:
	var junctions: Array = data.get("junctions", [])
	if junction_idx >= 0 and junction_idx < junctions.size():
		return junctions[junction_idx]
	return {}

func _register_hit(contact: Vector2, victim: Fighter, power: int) -> void:
	hit_done = true
	var sk: Dictionary = skill_by_index.get(skill_idx, {})
	var rate := 100
	for b in box_slots.values():
		if b["w"] > 0 and b["h"] > 0 and int(b.get("rate", 100)) != 100:
			rate = int(b.get("rate", 100))
	var lvl := int(sk.get("lvl", 0))
	var dmg: float
	if power < 0:
		# no FA power area on this move -> legacy level-based fallback
		dmg = float(20 + lvl) * float(rate) / 100.0
	else:
		dmg = float(power) * float(rate) / 100.0 * DMG_SCALE
	victim.hp = maxf(victim.hp - dmg, 0.0)
	var jref := _junction_ref()
	var jn := int(jref.get("j", 0))
	var entry: Dictionary = victim.junction_entry(jn if jn != 0 else 1)
	var react_skill := int(entry.get("j", 0))
	var spark_skill := int(entry.get("s", 0))
	if victim.hp <= 0.0:
		victim.enter_ko()
	else:
		victim.enter_reaction(react_skill)
	_spawn_spark(spark_skill, contact, victim)

## Victim reaction: play the junction gethit skill (own M-block knockback),
## falling back to plain hitstun when the junction has none.
func enter_reaction(gethit_skill_idx: int) -> void:
	if gethit_skill_idx == 0 or not skill_by_index.has(gethit_skill_idx):
		stun_t = 24
		state = "HITSTUN"
		move = Vector2.ZERO
		grav = Vector2.ZERO
		return
	_enter_skill(gethit_skill_idx, false)
	state = "HIT"
	move = Vector2.ZERO
	grav = Vector2.ZERO

func enter_ko() -> void:
	if ko:
		return
	ko = true
	stun_t = 0
	move = Vector2.ZERO
	grav = Vector2.ZERO
	play_builtin("loss", true)
	state = "KO"

## Spawn a junction hit spark as a one-shot effect (victim-defined skill).
func _spawn_spark(spark_skill: int, contact: Vector2, victim: Fighter) -> void:
	if spark_skill == 0 or not victim.skill_by_index.has(spark_skill):
		return
	var Effect := preload("res://scripts/effect.gd")
	var fx := Effect.new()
	var sk: Dictionary = victim.skill_by_index[spark_skill]
	fx.frames = sk.get("frames", [])
	fx.sound_events = sk.get("sounds", [])
	fx.images = victim.img_by_id
	fx.sound_bank = victim.snd_by_id
	fx.position = contact
	fx.use_frame_offset = false   # v0.3: spark art draws at the hit mark
	get_parent().add_child(fx)

func _draw() -> void:
	if not Data.show_boxes:
		return
	for b in box_slots.values():
		if b["w"] <= 0 or b["h"] <= 0:
			continue
		var col := Color(0, 0, 0, 0)
		if bool(b.get("col", false)):
			col = Color(1.0, 0.15, 0.15, 0.4)
		if bool(b.get("dmg", false)):
			col = Color(0.2, 0.6, 1.0, 0.4)
		if bool(b.get("thr", false)):
			col = Color(0.3, 1.0, 0.3, 0.4)
		var lx: float = (-float(b["x"]) - float(b["w"]) / 2) if facing == -1 else (float(b["x"]) - float(b["w"]) / 2)
		draw_box_rect(Rect2(lx, float(b["y"]) - float(b["h"]), float(b["w"]), float(b["h"])), col)
	for fa in fa_slots.values():
		if fa["w"] <= 0 or fa["h"] <= 0:
			continue
		var lx2: float = (-float(fa["x"]) - float(fa["w"]) / 2) if facing == -1 else (float(fa["x"]) - float(fa["w"]) / 2)
		_draw_force_rect(Rect2(lx2, float(fa["y"]) - float(fa["h"]), float(fa["w"]), float(fa["h"])))

func draw_box_rect(rect: Rect2, col: Color) -> void:
	draw_rect(rect, col, true)
	draw_rect(rect, Color(col.r, col.g, col.b, 1.0), false, 1.0)

func _draw_force_rect(rect: Rect2) -> void:
	draw_rect(rect, Color(1.0, 0.6, 0.1, 0.5), true)
	draw_rect(rect, Color(1.0, 0.6, 0.1, 1.0), false, 1.0)
	if stun_t > 0:
		_spr.modulate = Color(2.0, 0.7, 0.7)
	elif ko:
		_spr.modulate = Color(0.55, 0.55, 0.6)
	else:
		_spr.modulate = Color(1.0, 1.0, 1.0)
