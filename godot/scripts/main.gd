extends Node2D
## Main fight scene: FM2K-driven fighters on a compiled stage, authentic KGT
## HUD (life gauges, spirit gauge fills, victory marks, round timer digits)
## and the FM2K round/match flow driven by the KGT bank's own announcer
## skills ("Round N" / "Fight" / "Knock Out" / "Perfect" / "1P Wins" / ...).
##
## Match parameters are set by the character-select scene (static fields
## below); empty fields fall back to the manifest's first entries, which
## keeps the plain single-boot demo working.

const FIGHTER := preload("res://scripts/fighter.gd")
const SELECT_SCENE := "res://scenes/select.tscn"

static var p1_name := ""
static var p2_name := ""
static var stage_name := ""
static var demo_ai := true          # brain on p2 for the plain demo boot

var p1: Fighter
var p2: Fighter
var _bar1: ColorRect
var _bar2: ColorRect
var _meter1: ColorRect
var _meter2: ColorRect
var _hud_lbl: Label

# ------------------------------------------------------------- KGT HUD kit
var _kgt_skill: Dictionary = {}     # normalized name -> skill dict
var _kgt_img: Dictionary = {}       # image id -> {w, h, file}
var _kgt_snd: Dictionary = {}       # sound id -> file
var _audio: AudioStreamPlayer
var _card_layer: CanvasLayer
var _card_sprite: Sprite2D
var _flash: ColorRect               # stand-in for the engine's img 8191 white
var _card: Dictionary = {}          # active card {sk, i, t}
var _card_queue: Array = []         # queued announcer card names
var _chain_tag := ""                # "intro" | "ko" | "timeout"
var _hold := 0                      # settle ticks after a chain finishes
const CARD_SETTLE := 45
var card_history: Array[String] = []  # every announcer card (tests read this)

# ------------------------------------------------- round / match flow state
var _round := 1
var _wins := [0, 0]                 # FM2K: first to 2 rounds takes the match
var _awarded := false
var _phase := "boot"                # boot -> intro -> fight -> ko -> end
var _timer := 99                    # authentic 99-count round timer
var _timer_t := 0
var _winner := -1                   # winner side resolved at KO/timeout (-1 draw)
var _digit_ten: Sprite2D
var _digit_one: Sprite2D
var _pip_state := Vector2i(-1, -1)
var _pips1: Array[Sprite2D] = []
var _pips2: Array[Sprite2D] = []
var _paused := false
var _pause_pick := 0                # 0 resume, 1 back to character select
var _pause_layer: CanvasLayer
var _pause_hint: Label
var _pause_opts: Array[Label] = []
var touch_pad: Variant = null       # virtual FM2K touch overlay
var _end_t := 0                      # end-phase counter (victory pose settle)
var _cont_layer: CanvasLayer         # FM2K continue screen (authored art)
var _cont_digit: Sprite2D            # big KGT countdown digit
var _cont_t := 0
var _cont_num := 9

func _ready() -> void:
	_register_inputs()
	_load_kgt()

	_audio = AudioStreamPlayer.new()
	add_child(_audio)

	_card_layer = CanvasLayer.new()
	_card_layer.layer = 15
	add_child(_card_layer)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1)
	_flash.position = Vector2.ZERO
	_flash.size = Vector2(320, 240)
	_flash.visible = false
	_card_layer.add_child(_flash)
	_card_sprite = Sprite2D.new()
	_card_sprite.centered = false
	_card_sprite.visible = false
	_card_layer.add_child(_card_sprite)

	var man: Variant = Data.load_json("res://data/manifest.json")
	var chars: Array = (man.get("characters") if man != null else []) as Array
	var stages: Array = (man.get("stages") if man != null else []) as Array
	var ca := p1_name if p1_name != "" else (String(chars[0]) if chars.size() > 0 else "Applejack")
	var cb := p2_name if p2_name != "" else (String(chars[1]) if chars.size() > 1 else "Rainbow Dash")
	var st := stage_name if stage_name != "" else (String(stages[0]) if stages.size() > 0 else "Training Stage")

	_build_stage(st)

	p1 = _spawn(0, ca, Vector2(110, 0))
	p2 = _spawn(1, cb, Vector2(210, 0))
	p1.opp = p2
	p2.opp = p1
	p2.ai = demo_ai

	# virtual touch pad: feeds the same InputBuffer p1 uses; visible on
	# touch hardware or when the project emulates touches from the mouse
	var tc: Variant = preload("res://scripts/touch_controls.gd").new()
	tc.buf = p1.ibuf
	add_child(tc)
	touch_pad = tc
	var emu := bool(ProjectSettings.get_setting(
			"input_devices/pointing/emulate_touch_from_mouse", false))
	tc.visible = DisplayServer.is_touchscreen_available() or emu

	_build_hud(st, ca, cb)
	_build_pause_menu()
	_begin_round()

func _spawn(side: int, char_name: String, at: Vector2) -> Fighter:
	var f := FIGHTER.new()
	add_child(f)
	f.setup(char_name, side)
	f.pos = at
	return f

# ------------------------------------------------------------------ flow
## Round reset + the FM2K announcer chain ("Round N" or "Final Round" →
## "Fight"), fighters frozen until the chain lands them in the fight phase.
func _begin_round() -> void:
	_phase = "intro"
	_winner = -1
	_awarded = false
	_timer = 99
	_timer_t = 0
	_draw_timer()
	for f in [p1, p2]:
		f.frozen = true
		f.ko = false
		f.hp = f.max_hp
		f.stiff_t = 0
		f.stun_t = 0
		f.state = "IDLE"
		f.play_builtin("standing", true)
	p1.pos = Vector2(110, 0)
	p2.pos = Vector2(210, 0)
	p1.facing = 1
	p2.facing = -1
	var card := "Final Round" if (_wins[0] >= 1 and _wins[1] >= 1) else "Round %d" % _round
	_play_cards([card, "Fight"], "intro")

func _on_ko() -> void:
	if _phase != "fight":
		return
	_phase = "ko"
	var both := p1.ko and p2.ko
	_winner = _resolve_winner()
	var chain: Array[String] = ["Double Knock Out" if both else "Knock Out"]
	if _winner >= 0:
		var w := p1 if _winner == 0 else p2
		if w.hp >= w.max_hp - 0.5:
			chain.append("Perfect")
		chain.append("1P Wins" if _winner == 0 else "2P Wins")
	else:
		chain.append("Draw")
	_hold = 0
	_play_cards(chain, "ko")

func _on_timeout() -> void:
	_phase = "ko"
	_chain_tag = "timeout"
	_winner = _resolve_winner()
	p1.frozen = true
	p2.frozen = true
	var chain: Array[String] = ["TIME'S UP"]
	if _winner >= 0:
		var w := p1 if _winner == 0 else p2
		if w.hp >= w.max_hp - 0.5:
			chain.append("Perfect")
		chain.append("1P Wins" if _winner == 0 else "2P Wins")
	else:
		chain.append("Draw")
	_play_cards(chain, "timeout")

## Winner side at the moment of a stoppage; -1 = draw (double KO / tie).
func _resolve_winner() -> int:
	if p2.ko and not p1.ko:
		return 0
	if p1.ko and not p2.ko:
		return 1
	var r1 := p1.hp / maxf(p1.max_hp, 1.0)
	var r2 := p2.hp / maxf(p2.max_hp, 1.0)
	if absf(r1 - r2) < 0.01:
		return -1
	return 0 if r1 > r2 else 1

## Chain finished: award the round (first to 2 wins the match), then either
## the decider round intro or the match-end victory pose.
func _finish_round() -> void:
	if _winner >= 0 and not _awarded:
		_awarded = true
		_wins[_winner] += 1
	if _winner >= 0 and _wins[_winner] >= 2:
		_phase = "end"
		_end_t = 0
		var w := p1 if _winner == 0 else p2
		var l := p2 if _winner == 0 else p1
		w.frozen = false
		l.frozen = true
		w.play_builtin("victory")
		return
	_round += 1
	_begin_round()

# --------------------------------------------------------------- continue
## FM2K continue screen (demo-AI matches the human lost): the authored
## "Don't give up now!" art layers from the compiled Continue dump, a big
## 9..0 countdown in the timer digits, Enter/tap = YES rematch, Esc/timeout
## = NO game over back to the title.
func _start_continue() -> void:
	_phase = "continue"
	_cont_t = 0
	_cont_num = 9
	_cont_layer = CanvasLayer.new()
	_cont_layer.layer = 30
	add_child(_cont_layer)
	for f in ["0000", "0001", "0004", "0006", "0008"]:   # bg, give-up, word, yes, no
		var t := Data.tex("assets/continue/img/%s.png" % f)
		if t == null:
			continue
		var sp := Sprite2D.new()
		sp.texture = t
		sp.centered = false
		sp.scale = Vector2(0.5, 0.5)
		_cont_layer.add_child(sp)
	_cont_show_digit()
	var ln := Label.new()
	ln.text = "ENTER = YES   |   ESC = NO"
	ln.position = Vector2(0, 231)
	ln.size = Vector2(320, 9)
	ln.add_theme_font_size_override("font_size", 7)
	ln.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	_cont_layer.add_child(ln)
	var vs := Data.wav("assets/continue/snd/0001.wav")
	if vs != null:
		_audio.stream = vs
		_audio.play()

func _cont_show_digit() -> void:
	if _cont_layer == null:
		return
	var im: Dictionary = _kgt_img.get(239 + _cont_num, {})
	var tex: Texture2D = null
	if not im.is_empty():
		tex = Data.tex(String(im["file"]))
	if _cont_digit == null:
		_cont_digit = Sprite2D.new()
		_cont_digit.centered = true
		_cont_digit.scale = Vector2(2.0, 2.0)
		_cont_digit.position = Vector2(160, 104)
		_cont_layer.add_child(_cont_digit)
	_cont_digit.visible = tex != null
	if tex != null:
		_cont_digit.texture = tex

func _tick_continue() -> void:
	_cont_t += 1
	if _cont_t < 60:
		return
	_cont_t = 0
	_cont_num -= 1
	if _cont_num < 0:
		_do_continue(false)
		return
	_cont_show_digit()

func _do_continue(yes: bool) -> void:
	_free_continue()
	if yes:
		# authentic rematch: full reset, announcer chain restarts at Round 1
		_wins = [0, 0]
		_round = 1
		_begin_round()
	else:
		get_tree().change_scene_to_file("res://scenes/title.tscn")

func _free_continue() -> void:
	if _cont_layer != null:
		_cont_layer.queue_free()
		_cont_layer = null
	_cont_digit = null
	_cont_t = 0

func _input(event: InputEvent) -> void:
	# touch/mouse taps accept the continue (mobile parity with Enter)
	var t := event as InputEventScreenTouch
	if t != null and t.pressed and _phase == "continue":
		_do_continue(true)

# ------------------------------------------------------------- announcers
func _load_kgt() -> void:
	var k: Variant = Data.kgt()
	if k == null:
		return
	for sk in k.get("skills", []):
		_kgt_skill[String(sk["n"]).strip_edges().to_lower()] = sk
	for im in k.get("images", []):
		_kgt_img[int(im["id"])] = im
	for s in k.get("sounds", []):
		_kgt_snd[int(s["id"])] = String(s["file"])

func _play_cards(names: Array, tag: String) -> void:
	_card_queue = Array(names)
	_chain_tag = tag
	_advance_card()

func _advance_card() -> void:
	if _card_queue.is_empty():
		_stop_card()
		_hold = CARD_SETTLE      # settle pause before the chain resolves
		return
	var nm := String(_card_queue.pop_front())
	card_history.append(nm)
	var sk: Dictionary = _kgt_skill.get(nm.strip_edges().to_lower(), {})
	if sk.is_empty():
		push_warning("main: no KGT announcer skill '%s'" % nm)
		_advance_card()
		return
	_card = {"sk": sk, "i": 0, "t": 0}
	_show_card_frame()

## One card-frame step per process call (cards run on frame timings).
func _tick_card() -> void:
	if _card.is_empty():
		return
	_card["t"] = int(_card["t"]) + 1
	var sk: Dictionary = _card["sk"]
	var frames: Array = sk.get("frames", [])
	var i: int = mini(int(_card["i"]), frames.size() - 1)
	if i < 0 or frames.is_empty():
		_card = {}
		_stop_card()
		_advance_card()
		return
	var d := maxi(1, int(frames[i].get("d", 1)))
	if int(_card["t"]) < d:
		return
	_card["t"] = 0
	if i + 1 >= frames.size():
		_card = {}
		_stop_card()
		_advance_card()
	else:
		_card["i"] = i + 1
		_show_card_frame()

func _show_card_frame() -> void:
	var sk: Dictionary = _card["sk"]
	var frames: Array = sk.get("frames", [])
	if frames.is_empty():
		_card = {}
		_stop_card()
		_advance_card()
		return
	var i: int = mini(int(_card["i"]), frames.size() - 1)
	var fr: Dictionary = frames[i]
	var img_id := int(fr.get("i", 0))
	# authored img 8191 = the engine's full-screen white flash (not a file)
	_flash.visible = img_id == 8191
	_card_sprite.visible = img_id != 8191
	var im: Dictionary = _kgt_img.get(img_id, {})
	var tex: Texture2D = null
	if not im.is_empty():
		tex = Data.tex(String(im["file"]))
	if tex != null:
		_card_sprite.texture = tex
		_card_sprite.position = Vector2(float(fr.get("x", 0)) * 0.5, float(fr.get("y", 0)) * 0.5)
	for snd in sk.get("sounds", []):
		if int(snd.get("t", -1)) == i:
			_play_sfx(int(snd.get("s", 0)))

func _stop_card() -> void:
	_card_sprite.visible = false
	_flash.visible = false

func _play_sfx(snd_id: int) -> void:
	var file: String = _kgt_snd.get(snd_id, "")
	if file == "":
		return
	var st := Data.wav(file)
	if st != null:
		_audio.stream = st
		_audio.play()

func _chain_done() -> void:
	match _chain_tag:
		"intro":
			_phase = "fight"
			p1.frozen = false
			p2.frozen = false
		"ko", "timeout":
			_finish_round()

# ------------------------------------------------------------------ stage
func _build_stage(st: String) -> void:
	var slug := Fighter._slug(st)
	var data: Variant = Data.load_json("res://data/stages/%s.json" % slug)
	if data == null:
		return
	var chosen: Dictionary = {}
	for im in data.get("images", []):
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

# -------------------------------------------------------------------- HUD
func _build_hud(st: String, ca: String, cb: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	_mk_bar(layer, Vector2(0, 0), Vector2(320, 18), Color(0, 0, 0, 0.55))

	# health fills sit under the authentic gauge art (kgt '1P/2P Life Gauge')
	_bar1 = _mk_bar(layer, Vector2(3, 4), Vector2(116, 6), Color(0.2, 0.8, 0.3))
	_bar2 = _mk_bar(layer, Vector2(201, 4), Vector2(116, 6), Color(0.85, 0.7, 0.2))
	_meter1 = _mk_bar(layer, Vector2(2, 14), Vector2(118, 3), Color(0.55, 0.35, 0.9))
	_meter2 = _mk_bar(layer, Vector2(200, 14), Vector2(118, 3), Color(0.55, 0.35, 0.9))

	_add_life_art(layer, 0)          # gauge frame 130 left, 131 right
	_add_life_art(layer, 1)
	_add_pips(layer, 0)              # victory marks 132/133, two per player
	_add_pips(layer, 1)
	_add_timer(layer)                # 'Time Number' digits, authored set

	_hud_lbl = Label.new()
	_hud_lbl.text = "FM2K -> Godot  |  %s vs %s  |  %s" % [ca, cb, Fighter._slug(st).replace("_", " ")]
	_hud_lbl.position = Vector2(4, 222)
	_hud_lbl.add_theme_font_size_override("font_size", 8)
	layer.add_child(_hud_lbl)

func _mk_bar(layer: CanvasLayer, pos: Vector2, size: Vector2, col: Color) -> ColorRect:
	var back := ColorRect.new()
	back.position = pos
	back.size = size
	back.color = col
	layer.add_child(back)
	return back

func _add_life_art(layer: CanvasLayer, side: int) -> void:
	var sk: Dictionary = _kgt_skill.get("1p life gauge" if side == 0 else "2p life gauge", {})
	var frames: Array = sk.get("frames", [])
	if frames.is_empty():
		return
	var im: Dictionary = _kgt_img.get(int(frames[0].get("i", 0)), {})
	if im.is_empty():
		return
	var tex := Data.tex(String(im["file"]))
	if tex == null:
		return
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.scale = Vector2(0.5, 0.5)
	var w := float(im["w"]) * 0.5
	var h := float(im["h"]) * 0.5
	if side == 0:
		sp.position = Vector2(2 + w * 0.5, 1 + h * 0.5)
	else:
		sp.position = Vector2(320 - 2 - w * 0.5, 1 + h * 0.5)
		sp.flip_h = true
	layer.add_child(sp)

func _add_pips(layer: CanvasLayer, side: int) -> void:
	var yes: Dictionary = _kgt_img.get(132, {})
	var no: Dictionary = _kgt_img.get(133, {})
	if yes.is_empty() or no.is_empty():
		return
	var w := float(yes["w"]) * 0.5
	var h := float(yes["h"]) * 0.5
	for k in 2:
		var sp := Sprite2D.new()
		sp.scale = Vector2(0.5, 0.5)
		var x := 124 + w * 0.5 if side == 0 else 320.0 - 124.0 - w * 0.5
		var y := 4 + h * 0.5 + k * (h + 1)
		sp.position = Vector2(x, y)
		sp.flip_h = side == 1
		sp.texture = Data.tex(String(no["file"]))
		if side == 0:
			_pips1.append(sp)
		else:
			_pips2.append(sp)
		layer.add_child(sp)
	_update_pips(true)

func _update_pips(force: bool = false) -> void:
	var st := Vector2i(_wins[0], _wins[1])
	if not force and st == _pip_state:
		return
	_pip_state = st
	var on_tex: Dictionary = _kgt_img.get(132, {})
	var off_tex: Dictionary = _kgt_img.get(133, {})
	if on_tex.is_empty() or off_tex.is_empty():
		return
	for side in 2:
		var pips := _pips1 if side == 0 else _pips2
		var wins: int = _wins[side]
		for k in pips.size():
			var tex: Texture2D = Data.tex(String((on_tex if k < wins else off_tex)["file"]))
			if tex != null:
				pips[k].texture = tex

func _add_timer(layer: CanvasLayer) -> void:
	_digit_ten = _mk_digit(layer, 148)
	_digit_one = _mk_digit(layer, 162)
	_draw_timer()

func _mk_digit(layer: CanvasLayer, x: float) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.centered = false
	sp.scale = Vector2(0.5, 0.5)
	sp.position = Vector2(x, 24)
	layer.add_child(sp)
	return sp

## Authentic timer digits: authored 'Time Number N' images 239..248.
func _draw_timer() -> void:
	if _digit_ten == null:
		return
	for pair in [[_digit_ten, floori(_timer / 10.0)], [_digit_one, _timer % 10]]:
		var sp: Sprite2D = pair[0]
		var im: Dictionary = _kgt_img.get(239 + int(pair[1]), {})
		var tex: Texture2D = null
		if not im.is_empty():
			tex = Data.tex(String(im["file"]))
		sp.visible = tex != null
		if tex != null:
			sp.texture = tex
			# digit height varies: bottom-align the pair around y 36
			sp.position.y = 36.0 - float(im.get("h", 32)) * 0.5

# ------------------------------------------------------------------ pause
## Authentic pause: authored 'Pause' word skill (KGT 90, word img 53) over a
## dark overlay with plain Resume / Character-select options. Fighters freeze
## while paused.
func _toggle_pause(on: bool) -> void:
	if _pause_layer == null:
		return
	if on and (_phase != "fight" or _paused):
		return
	if not on and not _paused:
		return
	_paused = on
	_pause_layer.visible = on
	if on:
		_pause_pick = 0
		_pause_refresh()
		for f in [p1, p2]:
			f.frozen = true
	elif _phase == "fight":
		for f in [p1, p2]:
			f.frozen = false

func _pause_refresh() -> void:
	for k in _pause_opts.size():
		_pause_opts[k].add_theme_color_override("font_color",
				Color(1, 1, 1) if k == _pause_pick else Color(0.5, 0.55, 0.65))

func _build_pause_menu() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.layer = 20
	_pause_layer.visible = false
	add_child(_pause_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.position = Vector2.ZERO
	dim.size = Vector2(320, 240)
	_pause_layer.add_child(dim)

	var pause_sk: Dictionary = _kgt_skill.get("pause", {})
	for fr in pause_sk.get("frames", []):
		var im: Dictionary = _kgt_img.get(int(fr.get("i", 0)), {})
		if not im.is_empty() and int(im["id"]) != 8191:
			var tex := Data.tex(String(im["file"]))
			if tex != null:
				var sp := Sprite2D.new()
				sp.texture = tex
				sp.centered = false
				var w: float = float(im["w"]) * 0.5
				var h: float = float(im["h"]) * 0.5
				sp.scale = Vector2(0.5, 0.5)
				sp.position = Vector2(160.0 - w * 0.5, 70.0 - h * 0.5)
				_pause_layer.add_child(sp)
			break

	_pause_opts.append(_pause_label(Vector2(0, 140), 12))
	_pause_opts[0].text = "RESUME"
	_pause_opts.append(_pause_label(Vector2(0, 162), 12))
	_pause_opts[1].text = "CHARACTER SELECT"
	_pause_refresh()

func _pause_label(pos: Vector2, fsize: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(320, 18)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fsize)
	_pause_layer.add_child(l)
	return l

# ------------------------------------------------------------------ loop
func _process(_delta: float) -> void:
	# cards advance on the frame clock; between chains a settle hold runs
	if _card:
		_tick_card()
	elif _hold > 0:
		_hold -= 1
		if _hold == 0:
			_chain_done()

	if _bar1 == null or p1 == null:
		return
	var r1 := p1.hp / maxf(p1.max_hp, 1.0)
	var r2 := p2.hp / maxf(p2.max_hp, 1.0)
	_bar1.size.x = 116.0 * r1
	_bar2.size.x = 116.0 * r2
	if _meter1 != null:
		_meter1.size.x = 118.0 * (p1.meter / maxf(p1.meter_max, 1.0))
		_meter2.size.x = 118.0 * (p2.meter / maxf(p2.meter_max, 1.0))
	_update_pips()

	# round timer (decimal digits) during the fight phase
	if _phase == "fight" and not _paused:
		_timer_t += 1
		if _timer_t >= 60:
			_timer_t = 0
			_timer = maxi(0, _timer - 1)
			_draw_timer()
			if _timer == 0:
				_on_timeout()

	if _phase == "fight" and (p1.ko or p2.ko):
		_on_ko()

	if _phase == "end":
		_end_t += 1
		if _end_t == 150 and demo_ai and _winner == 1:
			# human lost the demo match: the FM2K continue screen offers a
			# rematch before the game-over returns to the title
			_start_continue()
	elif _phase == "continue":
		_tick_continue()
	if _phase == "continue":
		if Input.is_action_just_pressed("ui_accept"):
			_do_continue(true)
		elif Input.is_action_just_pressed("ui_cancel"):
			_do_continue(false)
	elif _phase == "end" and Input.is_action_just_pressed("ui_accept"):
		get_tree().change_scene_to_file(SELECT_SCENE)
	if Input.is_action_just_pressed("dbg_boxes"):
		Data.show_boxes = not Data.show_boxes
	if Input.is_action_just_pressed("dbg_touch") and touch_pad != null:
		touch_pad.visible = not touch_pad.visible

	# pause menu (authored KGT skill 'Pause' word, plain options beneath)
	if _paused:
		if Input.is_action_just_pressed("ui_down"):
			_pause_pick = mini(1, _pause_pick + 1)
			_pause_refresh()
		if Input.is_action_just_pressed("ui_up"):
			_pause_pick = maxi(0, _pause_pick - 1)
			_pause_refresh()
		if Input.is_action_just_pressed("ui_accept"):
			if _pause_pick == 0:
				_toggle_pause(false)
			else:
				_paused = false
				get_tree().change_scene_to_file(SELECT_SCENE)
		elif Input.is_action_just_pressed("ui_cancel"):
			_toggle_pause(false)
	elif _phase == "fight" and Input.is_action_just_pressed("ui_cancel"):
		_toggle_pause(true)

# ----------------------------------------------------------------- inputs
func _register_inputs() -> void:
	var map := {
		"p1_left": [KEY_A], "p1_right": [KEY_D], "p1_up": [KEY_W], "p1_down": [KEY_S],
		"p1_a": [KEY_J], "p1_b": [KEY_K], "p1_c": [KEY_L], "p1_d": [KEY_I], "p1_e": [KEY_U],
		"p2_left": [KEY_LEFT], "p2_right": [KEY_RIGHT], "p2_up": [KEY_UP],
		"p2_down": [KEY_DOWN], "p2_a": [KEY_KP_1], "p2_b": [KEY_KP_2],
		"p2_c": [KEY_KP_3], "p2_d": [KEY_KP_4], "p2_e": [KEY_KP_5],
		"dbg_boxes": [KEY_F1],
		"dbg_touch": [KEY_F3],
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
