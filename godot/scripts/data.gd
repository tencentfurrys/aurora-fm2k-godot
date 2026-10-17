extends Node
## Data autoload — compiled FM2K data + lazy image & sound caches.
## JSONs live in res://data/... (native sprites/sounds under data/assets/*,
## which are .gdignore'd so the editor never imports them).

const DATA_DIR := "res://data/"

var _json: Dictionary = {}
var _tex: Dictionary = {}
var _wav: Dictionary = {}
var _kgt_cache: Variant = null

## Compiled KGT common skills (hit sparks, effects) for junction lookups.
func kgt() -> Variant:
	if _kgt_cache == null:
		_kgt_cache = load_json("res://data/kgt.json")
	return _kgt_cache

func kgt_skill_by_name(name: String) -> Dictionary:
	var k: Variant = kgt()
	if k == null:
		return {}
	for sk in k.get("skills", []):
		if sk["n"] == name:
			return sk
	return {}

## kgt images array -> {id: {w,h,file}} map (lazily cached).
func kgt_images() -> Dictionary:
	var k: Variant = kgt()
	if k == null:
		return {}
	if _kgt_images_cache.is_empty() and k.get("images", []) is Array:
		for im in k["images"]:
			_kgt_images_cache[int(im["id"])] = im
	return _kgt_images_cache

func kgt_sounds() -> Array:
	var k: Variant = kgt()
	return (k.get("sounds", []) if k != null else []) as Array

var _kgt_images_cache: Dictionary = {}

## F1 debug: draw active FD boxes.
var show_boxes := false

## Training-menu toggles (the FM2K training options; persisted user-side).
var auto_tech := false
var auto_heal := false
var lo_fi := false

## Headless-test hook: when true, scene exits (pause -> title) are recorded
## on flags instead of actually changing scenes.
var suppress_exit := false

const SETTINGS_PATH := "user://aurora_settings.cfg"

func load_json(res_path: String) -> Variant:
	if _json.has(res_path):
		return _json[res_path]
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		push_warning("Data: cannot open %s" % res_path)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	_json[res_path] = parsed
	return parsed

# ----------------------------------------------------------------- images ---
## res_rel_path is the "file" field stored in compiled JSON, e.g.
## "assets/applejack/img/0001.png". Loaded straight from disk via absolute
## path so the (gdignored) asset folder does not need editor import.
static func _abs_data_file(res_rel: String) -> String:
	return ProjectSettings.globalize_path(DATA_DIR + res_rel)

func tex(res_rel: String) -> Texture2D:
	if _tex.has(res_rel):
		return _tex[res_rel]
	var t: Texture2D = null
	# dev/editor runs: the raw source png is on disk, decode it directly
	var img := Image.load_from_file(_abs_data_file(res_rel))
	if img != null:
		t = ImageTexture.create_from_image(img)
	if t == null:
		# exported builds: the source png was imported (remapped away), so
		# load the generated texture resource instead
		var rl := ResourceLoader.load(DATA_DIR + res_rel, "Texture2D")
		if rl is Texture2D:
			t = rl
	_tex[res_rel] = t
	return t

func index_images(images: Array) -> Dictionary:
	var out := {}
	for im in images:
		out[int(im["id"])] = im
	return out

# ----------------------------------------------------------------- sounds ---
func wav(res_rel: String) -> AudioStreamWAV:
	if _wav.has(res_rel):
		return _wav[res_rel]
	var s: AudioStreamWAV = null
	# dev/editor runs: parse the raw file ourselves
	var f := FileAccess.open(DATA_DIR + res_rel, FileAccess.READ)
	if f != null:
		s = _parse_wav(f.get_buffer(f.get_length()))
	if s == null:
		# exported builds: the wav was imported (or kept raw via the
		# include filter); fall back to the resource
		var rl := ResourceLoader.load(DATA_DIR + res_rel, "AudioStreamWAV")
		if rl is AudioStreamWAV:
			s = rl
	if s != null:
		_wav[res_rel] = s
	return s

func _parse_wav(b: PackedByteArray) -> AudioStreamWAV:
	var ba := StreamPeerBuffer.new()
	ba.data_array = b
	if b.size() < 12:
		return null
	ba.seek(8)
	if ba.get_string(4) != "WAVE":
		return null
	var ch := 1
	var rate := 44100
	var data := PackedByteArray()
	var got_data := false
	while ba.get_position() + 8 <= b.size():
		var chunk := ba.get_string(4)
		var size := ba.get_u32()
		var end_pos := ba.get_position() + size
		if chunk == "fmt ":
			ba.get_u32()        # format tag (PCM)
			ch = ba.get_u16()
			rate = ba.get_u32()
			ba.get_u32()        # byte rate
			ba.get_u16()        # block align
			ba.get_u16()        # bits per sample
		elif chunk == "data":
			data = ba.get_data(size)
			got_data = true
		ba.seek(end_pos + (size % 2))
	if not got_data or data.size() == 0:
		return null
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.stereo = ch == 2
	s.mix_rate = rate
	s.data = data
	return s

# ------------------------------------------------------------- dev shots
## Screenshot hook for visual QA (windowed runs):
##   godot --path . -- --shot=<path.png> --shot-frame=<n> [--scene=<name>]
## The title scene honors --scene= to jump straight to another screen;
## headless runs never render, so this is used with windowed binaries.
## --shot-menu makes the main scene open the training menu, --shot-page=
## selects which menu page is shown (0 rows / 1 toggles / 2 cards / 3 stage).
var _shot_path := ""
var _shot_at := -1
var _shot_f := 0
var shot_menu := false
var shot_page := -1

func _ready() -> void:
	_load_settings()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-frame="):
			_shot_at = int(a.substr(13))
		elif a == "--shot-menu":
			shot_menu = true
		elif a.begins_with("--shot-page="):
			shot_page = int(a.substr(12))

## Persist the training menu toggles in user:// (desktop and APK both).
func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	show_boxes = bool(cf.get_value("training", "debug_button", false))
	auto_tech = bool(cf.get_value("training", "auto_tech", false))
	auto_heal = bool(cf.get_value("training", "auto_heal", false))
	lo_fi = bool(cf.get_value("training", "lo_fi", false))

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("training", "debug_button", show_boxes)
	cf.set_value("training", "auto_tech", auto_tech)
	cf.set_value("training", "auto_heal", auto_heal)
	cf.set_value("training", "lo_fi", lo_fi)
	cf.save(SETTINGS_PATH)

## Test helper: wipe persisted training state + the settings file so headless
## tests start deterministic no matter which order they run in.
func reset_for_tests() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(SETTINGS_PATH):
		dir.remove(SETTINGS_PATH)
	show_boxes = false
	auto_tech = false
	auto_heal = false
	lo_fi = false
	suppress_exit = false

func _process(_d: float) -> void:
	if _shot_at < 0 or _shot_path == "":
		return
	_shot_f += 1
	if _shot_f >= _shot_at:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		print("SHOT-SAVED: ", _shot_path)
		get_tree().quit()
