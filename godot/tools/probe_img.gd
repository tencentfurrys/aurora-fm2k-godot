extends SceneTree

func _initialize() -> void:
	var rels: PackedStringArray = [
		"assets/cadence/img/0000.png",
		"assets/cadence/img/0001.png",
		"assets/luna/img/0000.png",
		"assets/luna/img/0001.png",
		"assets/applejack/img/0000.png",
		"assets/rainbow_dash/img/0000.png",
		"assets/training_stage/img/0011.png",
		"assets/options/img/0008.png",
		"assets/title/img/0000.png",
	]
	var base: String = "res://data/"
	for rel: String in rels:
		var path_res: String = base + rel
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path_res))
		if img == null:
			print(rel, ": LOAD FAILED")
			continue
		var transp: int = 0
		var partial: int = 0
		var min_a: int = 255
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = 12345
		var area: int = img.get_width() * img.get_height()
		var samples: int = mini(4000, area)
		for i: int in samples:
			var x: int = rng.randi_range(0, img.get_width() - 1)
			var y: int = rng.randi_range(0, img.get_height() - 1)
			var a: int = int(img.get_pixel(x, y).a * 255.0)
			if a < min_a:
				min_a = a
				if a == 0:
					transp += 1
				elif a < 255:
					partial += 1
		print("%s: %dx%d fmt=%s min_alpha=%d n_transparent=%d n_partial=%d" % [
			rel, img.get_width(), img.get_height(), img.get_format(), min_a, transp, partial])
	quit()
