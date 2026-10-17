extends Node2D
## Character select + stage + versus flow, FM2K-style sequential picks.
## Portraits prefer each fighter's authored charSelectPic builtin; characters
## whose select art lives in the un-banked 8191 image slot fall back to their
## standing pose frame. Enter advances, Esc steps back one screen.

const MAIN := preload("res://scripts/main.gd")
const TILES_PER_ROW := 7
const TILE_ORIGIN := Vector2(20, 48)
const TILE_STEP := Vector2(42, 54)

var roster: Array = []          # [{name, sprite}]
var origins: Array[Vector2] = []
var stages: Array = []
var _stage_prev: Sprite2D           # stage-pick preview from the stage bank
var phase := 0                  # 0 p1 pick, 1 p2 pick, 2 stage, 3 ready
var cur := Vector2i(0, 0)       # shared pick cursor per phase
var cur_stage := 0
var p1_pick := -1
var p2_pick := -1
var cursor: ColorRect
var cursor2: ColorRect
var header: Label
var sub: Label
var footer: Label
var _t := 0.0

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)

	_bg(layer)

	var man: Variant = Data.load_json("res://data/manifest.json")
	var chars: Array = (man.get("characters") if man != null else []) as Array
	stages = (man.get("stages") if man != null else []) as Array
	var portraits := preload("res://scripts/select_portraits.gd")
	var tiles: Dictionary = portraits.tiles(chars)

	for c_name in chars:
		if String(c_name) == "Mode Select":
			continue          # menu dummy: no combat tables on any branch
		var pf: Dictionary = tiles.get(String(c_name), {})
		var tex: Texture2D = portraits.tex_for(pf)
		if tex == null and pf.is_empty():
			# no authored select tile: resolve the fighter's own pose
			var d: Variant = Data.load_json("res://data/characters/%s.json" % Fighter._slug(String(c_name)))
			if d != null:
				var f := _portrait(d)
				if f != "":
					tex = Data.tex(f)
		if tex == null:
			continue
		var idx := roster.size()
		var col := idx % TILES_PER_ROW
		var row := floori(float(idx) / float(TILES_PER_ROW))
		var tile := TILE_ORIGIN + Vector2(col, row) * TILE_STEP
		origins.append(tile)
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.centered = false
		img_fit(sp, tex, tile)
		layer.add_child(sp)
		var ln := Label.new()
		ln.text = String(c_name)
		ln.position = tile + Vector2(-11, 39)
		ln.size = Vector2(44, 15)
		ln.autowrap_mode = TextServer.AUTOWRAP_WORD
		ln.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ln.add_theme_font_size_override("font_size", 5)
		ln.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
		layer.add_child(ln)
		roster.append({"name": String(c_name)})

	cursor = _cursor(layer, Color(0.2, 0.9, 0.4, 0.35))
	cursor2 = _cursor(layer, Color(0.95, 0.6, 0.15, 0.35))
	cursor2.visible = false

	header = _label(layer, "PLAYER 1 — pick your fighter", Vector2(0, 8), 12, Color(1, 1, 1), Vector2(320, 16))
	sub = _label(layer, "", Vector2(0, 96), 16, Color(0.98, 0.72, 0.2), Vector2(320, 22))
	footer = _label(layer, "", Vector2(0, 222), 7, Color(0.5, 0.55, 0.65), Vector2(320, 12))
	_refresh_text()

func _process(delta: float) -> void:
	_t += delta
	_draw_cursors()
	match phase:
		0, 1:
			if Input.is_action_just_pressed("ui_left"):
				_move(-1, 0)
			if Input.is_action_just_pressed("ui_right"):
				_move(1, 0)
			if Input.is_action_just_pressed("ui_up"):
				_move(0, -1)
			if Input.is_action_just_pressed("ui_down"):
				_move(0, 1)
			if Input.is_action_just_pressed("ui_accept"):
				_confirm_pick()
			if Input.is_action_just_pressed("ui_cancel"):
				_back()
		2:
			if Input.is_action_just_pressed("ui_left"):
				_cycle_stage(-1)
			if Input.is_action_just_pressed("ui_right"):
				_cycle_stage(1)
			if Input.is_action_just_pressed("ui_accept"):
				phase = 3
				_refresh_text()
			if Input.is_action_just_pressed("ui_cancel"):
				phase = 1
				cursor.visible = true
				cursor2.visible = true
				_refresh_text()
		3:
			if Input.is_action_just_pressed("ui_accept"):
				_launch()
			if Input.is_action_just_pressed("ui_cancel"):
				phase = 2
				_refresh_text()

# ------------------------------------------------------------------ flow
## Confirm the highlighted fighter for the currently-picking player.
func _confirm_pick() -> void:
	cur.x = 0
	if phase == 0:
		p1_pick = cur.y
		phase = 1
		cursor2.visible = true
	else:
		p2_pick = cur.y
		phase = 2
	_refresh_text()

## Stage pick confirm (shared by Enter and center taps).
func _confirm_stage() -> void:
	phase = 3
	_refresh_text()

## Touch taps: mirror the menu flow - tap a tile to place the cursor, tap the
## already-highlighted tile to confirm; stage halves cycle, middle band
## confirms; ready screen tap launches.
func _input(event: InputEvent) -> void:
	var t := event as InputEventScreenTouch
	if t == null or not t.pressed:
		return
	_touch_tap(Vector2(t.position))

func _touch_tap(pos: Vector2) -> void:
	if phase <= 1:
		var best := -1
		for i in origins.size():
			var c: Vector2 = origins[i] + Vector2(22, 22)
			if c.distance_to(pos) <= 26.0:
				best = i
				break
		if best < 0:
			return
		var prev := cur.y
		cur.x = best % TILES_PER_ROW
		cur.y = best
		_refresh_text()
		if prev == best:
			_confirm_pick()
	elif phase == 2:
		if pos.x < 110:
			_cycle_stage(-1)
		elif pos.x > 210:
			_cycle_stage(1)
		else:
			_confirm_stage()
	else:
		_launch()

func _move(dx: int, dy: int) -> void:
	var n := maxi(1, roster.size())
	var y := cur.y
	var x := cur.x
	if dx != 0:
		# linear wraparound across the whole grid
		y = (((cur.y + dx) % n) + n) % n
		x = y % TILES_PER_ROW
	elif dy < 0:
		y = maxi(0, cur.y - TILES_PER_ROW)
		x = cur.x
	elif dy > 0:
		y = mini(n - 1, cur.y + TILES_PER_ROW)
		x = cur.x
	# final clamp: a partial last row can leave x past its end
	var li := mini(y + x, n - 1)
	cur = Vector2i(li % TILES_PER_ROW, li)
	_refresh_text()

func _cycle_stage(dir: int) -> void:
	if stages.is_empty():
		return
	cur_stage = (((cur_stage + dir) % stages.size()) + stages.size()) % stages.size()
	_refresh_text()

## Stage-pick preview: the compiled stage's widest authenticked art, shown
## from the stage phase onward (visible through the ready screen too).
func _stage_bg_refresh() -> void:
	if stages.is_empty():
		return
	var slug := Fighter._slug(String(stages[cur_stage]))
	var d: Variant = Data.load_json("res://data/stages/%s.json" % slug)
	var tex: Texture2D = null
	if d != null:
		var best: Dictionary = {}
		var best_area := 0.0
		for im in d.get("images", []):
			var area := float(im["w"]) * float(im["h"])
			if area > best_area:
				best_area = area
				best = im
		if not best.is_empty():
			tex = Data.tex(String(best["file"]))
	if tex != null:
		_stage_prev.texture = tex
	_stage_prev.visible = tex != null and phase >= 2

func _back() -> void:
	if phase == 0:
		get_tree().change_scene_to_file("res://scenes/title.tscn")
	elif phase == 1:
		cursor2.visible = false
		phase = 0
		p1_pick = -1
		_refresh_text()

func _launch() -> void:
	MAIN.p1_name = String(roster[p1_pick]["name"])
	MAIN.p2_name = String(roster[p2_pick]["name"])
	MAIN.stage_name = String(stages[cur_stage])
	MAIN.demo_ai = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

# ---------------------------------------------------------------- drawing
func _draw_cursors() -> void:
	if phase < 2:
		if cur.y >= 0 and cur.y < origins.size():
			cursor.position = origins[cur.y] - Vector2(3, 3)
	if p1_pick >= 0 and p1_pick < origins.size():
		cursor.position = origins[p1_pick] - Vector2(3, 3)   # lock onto p1 tile
	if phase == 1 and cur.y < origins.size():
		cursor2.position = origins[cur.y] - Vector2(3, 3)
	cursor2.visible = phase == 1
	cursor.visible = phase <= 2

func _refresh_text() -> void:
	_stage_bg_refresh()
	match phase:
		0:
			header.text = "PLAYER 1 — pick your fighter"
			header.add_theme_color_override("font_color", Color(0.45, 0.95, 0.6))
			sub.text = ""
			footer.text = "arrows: move    ENTER: confirm    ESC: back"
		1:
			header.text = "PLAYER 2 — pick your fighter"
			header.add_theme_color_override("font_color", Color(1, 0.75, 0.3))
			sub.text = ""
			footer.text = "arrows: move    ENTER: confirm"
		2:
			header.text = "SELECT STAGE"
			header.add_theme_color_override("font_color", Color(1, 1, 1))
			sub.text = String(stages[cur_stage]) if stages.size() > 0 else ""
			footer.text = "left/right: stage    ENTER: confirm    ESC: picks"
			_t = 10.0
		3:
			var a := String(roster[p1_pick]["name"]) if p1_pick >= 0 else "?"
			var b := String(roster[p2_pick]["name"]) if p2_pick >= 0 else "?"
			header.text = ""
			sub.text = "%s  VS  %s" % [a, b]
			footer.text = "ENTER: fight!    ESC: stage"
			_t = 6.0

# ---------------------------------------------------------------- helpers
func _bg(layer: CanvasLayer) -> void:
	var r := ColorRect.new()
	r.position = Vector2.ZERO
	r.size = Vector2(320, 240)
	r.color = Color(0.02, 0.02, 0.04)
	layer.add_child(r)
	# authentic title-family art, dimmed behind the pick grid
	var tex := Data.tex("assets/title/img/0000.png")
	if tex != null:
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.centered = false
		sp.scale = Vector2(0.5, 0.5)
		sp.modulate = Color(0.55, 0.58, 0.66)
		layer.add_child(sp)
	# the authored select-screen logo
	var lg := Data.tex("assets/character_select/img/0002.png")
	if lg != null:
		var ls := Sprite2D.new()
		ls.texture = lg
		ls.centered = false
		ls.scale = Vector2(0.5, 0.5)
		ls.position = Vector2(4, 2)
		ls.modulate = Color(1, 1, 1, 0.9)
		layer.add_child(ls)
	# stage-pick preview (compiled stage art, brightened on phase 2)
	_stage_prev = Sprite2D.new()
	_stage_prev.centered = false
	_stage_prev.scale = Vector2(0.5, 0.5)
	_stage_prev.position = Vector2.ZERO
	_stage_prev.visible = false
	layer.add_child(_stage_prev)

func _cursor(layer: CanvasLayer, col: Color) -> ColorRect:
	var c := ColorRect.new()
	c.position = origins[0] if origins.size() > 0 else Vector2.ZERO
	c.size = Vector2(46, 50)
	c.color = col
	layer.add_child(c)
	return c

func _label(layer: CanvasLayer, txt: String, pos: Vector2, fsize: int, col: Color, size: Vector2) -> Label:
	var l := Label.new()
	l.text = txt
	l.position = pos
	l.size = size
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	layer.add_child(l)
	return l

## Portrait resolution: authored charSelectPic when its image bank resolves,
## otherwise the standing pose frame, otherwise any resolvable skill frame.
func _portrait(d: Dictionary) -> String:
	var builtin: Dictionary = d.get("builtin", {})
	var images := Data.index_images(d.get("images", []))
	for key in ["charSelectPic", "standing"]:
		var idx := int(builtin.get(key, -1))
		if idx < 0:
			continue
		for sk in d.get("skills", []):
			if int(sk["i"]) != idx:
				continue
			for fr in sk.get("frames", []):
				var im: Dictionary = images.get(int(fr.get("i", 0)), {})
				if not im.is_empty():
					return String(im["file"])
	for sk in d.get("skills", []):
		for fr in sk.get("frames", []):
			var im: Dictionary = images.get(int(fr.get("i", 0)), {})
			if not im.is_empty():
				return String(im["file"])
	return ""

func img_fit(sp: Sprite2D, tex: Texture2D, tile: Vector2) -> void:
	var w := tex.get_width()
	var h := tex.get_height()
	var s := minf(40.0 / float(maxi(1, w)), 38.0 / float(maxi(1, h)))
	sp.scale = Vector2(s, s)
	sp.position = tile + Vector2(20 - w * s * 0.5, 12 - h * s * 0.5)
