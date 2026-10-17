extends Node2D
## Headless data smoke: every stage in the manifest must have a compiled json
## with at least one usable image whose PNG loads, and every roster fighter
## must have its json + standing builtin. Prints STAGE-TEST-PASS/FAIL.

func _ready() -> void:
	Data.reset_for_tests()
	var man: Variant = Data.load_json("res://data/manifest.json")
	var stages: Array = (man.get("stages") if man != null else []) as Array
	var chars: Array = (man.get("characters") if man != null else []) as Array
	var ok := stages.size() >= 27 and chars.size() >= 21
	var bad: Array[String] = []
	for st_name in stages:
		var slug := Fighter._slug(String(st_name))
		var d: Variant = Data.load_json("res://data/stages/%s.json" % slug)
		if d == null:
			bad.append(slug + ":no-json")
			continue
		var chosen: Dictionary = {}
		for im in d.get("images", []):
			if int(im["w"]) > 0 and int(im["h"]) > 0 and String(im["file"]) != "":
				chosen = im
				break
		if chosen.is_empty():
			bad.append(slug + ":no-img")
			continue
		if Data.tex(String(chosen["file"])) == null:
			bad.append(slug + ":no-tex")
	for c_name in chars:
		if String(c_name) == "Mode Select":
			continue          # menu dummy: compiled with no builtin tables
		var d2: Variant = Data.load_json("res://data/characters/%s.json" % Fighter._slug(String(c_name)))
		if d2 == null:
			bad.append(String(c_name) + ":no-json")
			continue
		var builtin: Dictionary = d2.get("builtin", {})
		if int(builtin.get("standing", -1)) < 0:
			bad.append(String(c_name) + ":no-standing")
	print("STAGE RESULT: stages=%d chars=%d bad=[%s]" % [stages.size(), chars.size(), ", ".join(bad)])
	print("STAGE-TEST-PASS" if ok and bad.is_empty() else "STAGE-TEST-FAIL")
	get_tree().quit()
