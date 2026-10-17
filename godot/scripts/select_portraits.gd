extends RefCounted
## Authentic character-select portraits sourced from the compiled
## "Character Select" scene dump: the expanded roster owns authored
## per-fighter tiles (50x44), and the six mains are sliced out of the
## authored "Mane 6" group sheet (two columns x three rows of hex portraits).
## Roster names with no authored tile return an empty dict so the caller can
## fall back to the fighter's own standing pose.

## Authored sheet layout of assets/character_select/img/0009.png (87x151):
## a 2x3 grid of 44x50 hex portraits, left column top-to-bottom AJ /
## Fluttershy / Pinkie, right column Twilight / Rainbow Dash / Rarity.
const SHEET_FILE := "assets/character_select/img/0009.png"
const SHEET_REGIONS := {
	"Applejack": Rect2(0, 0, 43, 50),
	"Twilight Sparkle": Rect2(43, 0, 44, 50),
	"Fluttershy": Rect2(0, 50, 43, 50),
	"Rainbow Dash": Rect2(43, 50, 44, 50),
	"Pinkie Pie": Rect2(0, 100, 43, 51),
	"Rarity": Rect2(43, 100, 44, 50),
}

## roster name -> {file} | {file, region}; empty dict = no authored tile.
static func tiles(roster_names: Array) -> Dictionary:
	var out := {}
	for name in SHEET_REGIONS:
		out[name] = {"file": SHEET_FILE, "region": SHEET_REGIONS[name]}
	var d: Variant = Data.load_json("res://data/demos/character_select.json")
	if d == null:
		return out
	var imgs: Dictionary = Data.index_images(d.get("images", []))
	for cname in roster_names:
		var key := String(cname).to_lower().replace(" ", "")
		if key == "" or out.has(String(cname)):
			continue
		for sk in d.get("skills", []):
			var sn := String(sk.get("n", "")).to_lower().replace(" ", "")
			if sn == "":
				continue
			# authored 'Big Mac' vs roster 'Big Macintosh', else exact
			if not (sn == key or key.begins_with(sn) or sn.begins_with(key)):
				continue
			var fr: Array = sk.get("frames", [])
			if fr.is_empty():
				continue
			var im: Dictionary = imgs.get(int(fr[0].get("i", -1)), {})
			if im.is_empty():
				continue
			out[String(cname)] = {"file": String(im["file"])}
			break
	return out

## Convenience: build the display texture for a tiles() entry (AtlasTexture
## slice for sheet entries), or null when absent/unloadable.
static func tex_for(entry: Dictionary) -> Texture2D:
	if not entry.has("file"):
		return null
	var base := Data.tex(String(entry["file"]))
	if base == null:
		return null
	if entry.has("region"):
		var at := AtlasTexture.new()
		at.atlas = base
		at.region = entry["region"]
		return at
	return base
