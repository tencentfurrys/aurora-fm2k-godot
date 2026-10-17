class_name FM2KEffect
extends Node2D
## One-shot effect that walks a compiled skill's frame list (hit sparks) and
## frees itself at the end. Images/sounds come from the character whose
## junction table defines the spark (per-character sparks in FM2K).

var frames: Array = []
var sound_events: Array = []
var images: Dictionary = {}            # image id -> {w,h,file}
var sound_bank: Dictionary = {}        # sound id -> file
var frame_pos := 0
var frame_t := 0
var use_frame_offset := false         # false: draw art centered on node origin
var _spr: Sprite2D
var _audio: AudioStreamPlayer

func _ready() -> void:
	_spr = Sprite2D.new()
	_spr.centered = true
	_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_spr)
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	z_index = 3
	if frames.is_empty():
		queue_free()

func _physics_process(_delta: float) -> void:
	if frames.is_empty():
		return
	var fr: Dictionary = frames[frame_pos]
	if frame_t == 0:
		for ev in sound_events:
			if int(ev["t"]) == frame_pos:
				_play(int(ev["s"]))
	_update_frame(fr)
	frame_t += 1
	if fr.get("hold") == 1:
		queue_free()
		return
	if frame_t >= int(fr["d"]):
		frame_t = 0
		frame_pos += 1
		if frame_pos >= frames.size():
			queue_free()

func _update_frame(fr: Dictionary) -> void:
	var meta: Dictionary = images.get(int(fr["i"]), {})
	if meta.is_empty():
		_spr.visible = false
		return
	_spr.visible = true
	var t := Data.tex(String(meta["file"]))
	if t != null:
		_spr.texture = t
	_spr.flip_h = bool(fr.get("fx", false))
	_spr.flip_v = bool(fr.get("fy", false))
	if use_frame_offset:
		_spr.position = Vector2(float(fr["x"]), float(fr["y"]))
	else:
		_spr.position = Vector2.ZERO

func _play(sound_id: int) -> void:
	var file: String = sound_bank.get(sound_id, "")
	if file == "":
		return
	var st := Data.wav(file)
	if st != null:
		_audio.stream = st
		_audio.play()
