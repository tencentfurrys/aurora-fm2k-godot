import json, glob, os, sys

SRC = r"C:\Users\RDP\AppData\Local\Temp\1\opencode\aurora-fm2k-godot\aurora_fm2k"
OUT = r"C:\Users\RDP\AppData\Local\Temp\1\opencode\aurora-fm2k-godot\godot\data\stage_parallax.json"

def slugify(name):
    return name.lower().replace("'", "").replace("! ", "").replace("!", "").replace("(", " ").replace(")", " ").replace("-", " ").replace(".", " ").replace("  ", " ").replace("  ", " ").strip().replace(" ", "_")

out = {}
for path in glob.glob(os.path.join(SRC, "*.json")):
    base = os.path.splitext(os.path.basename(path))[0]
    if base in ("Aurora", "Training"):
        # 'Training' is a demo/kgt bank, Aurora is the master index
        if base == "Aurora":
            continue
    try:
        d = json.load(open(path, encoding="utf-8"))
    except Exception as e:
        print("skip", base, e)
        continue
    layers = {}
    for sk in d.get("skills", []):
        st = sk.get("settings") or {}
        w = st.get("width")
        h = st.get("height")
        if w is None or h is None:
            continue
        nm = sk.get("name") or ""
        layers[nm] = [int(w), int(h)]
    if layers:
        out[slugify(base.replace(".json", ""))] = layers
        print(base, "->", len(layers), "layers")

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(out, f, separators=(",", ":"))
print("wrote", OUT, len(out), "stages")
