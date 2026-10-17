extends Node
# Frame-capture helper for offline debugging (PC only, not part of the game).
# Usage:
#   CAPTURE_SCENE=res://scenes/title.tscn CAPTURE_STAMPS=2,10 godot res://tools/capture.tscn
# Saves PNGs to D:/tools/pc-capture/ and quits.

func _ready() -> void:
	var scene_path := OS.get_environment("CAPTURE_SCENE")
	if scene_path == "":
		scene_path = "res://scenes/title.tscn"
	var stamps := []
	var raw := OS.get_environment("CAPTURE_STAMPS")
	if raw != "":
		for s in raw.split(","):
			if s.strip_edges() != "":
				stamps.append(float(s))
	var tag: String = scene_path.get_file().get_basename()
	# optional static overrides for the main scene (stage / picks)
	var stage_env := OS.get_environment("CAPTURE_STAGE")
	if stage_env != "" and scene_path.ends_with("main.tscn"):
		var msc: GDScript = load("res://scripts/main.gd")
		msc.set("stage_name", stage_env)
		msc.set("p1_name", "Luna")
		msc.set("p2_name", "Cadence")
	var dir := "D:/tools/pc-capture"
	DirAccess.make_dir_recursive_absolute(dir)
	add_child(load(scene_path).instantiate())
	for t in stamps:
		await get_tree().create_timer(t).timeout
		var img: Image = get_viewport().get_texture().get_image()
		var out := "%s/%s-t%d.png" % [dir, tag, int(t)]
		img.save_png(out)
		print("CAPTURED: ", out)
	get_tree().quit()
