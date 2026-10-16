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
	var img := Image.load_from_file(_abs_data_file(res_rel))
	if img == null:
		return null
	var t := ImageTexture.create_from_image(img)
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
	var f := FileAccess.open(DATA_DIR + res_rel, FileAccess.READ)
	if f == null:
		return null
	var s := _parse_wav(f.get_buffer(f.get_length()))
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
