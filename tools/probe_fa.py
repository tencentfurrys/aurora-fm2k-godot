import json, os

SRCA = r"C:\Users\RDP\Documents\Default Project\aurora_fm2k"
d = json.load(open(os.path.join(SRCA, "Applejack.json")))
byn = {s["name"].strip(): s for s in d["skills"]}

for nm in ("Standing Light", "Standing Mid", "Standing Heavy", "Crouching Light", "Crouching Mid"):
    s = byn.get(nm)
    if not s:
        continue
    print(f"== {nm} (idx {s['index']}, lvl={s.get('settings') or {}})")
    for b in s["blocks"]:
        t = b["type"]
        if t == "FA":
            print("  FA:", {k: b[k] for k in ("x", "y", "width", "height", "number", "power", "cancel", "combo", "halfed", "duringGuard") if k in b})
        elif t == "FD":
            print("  FD:", {k: b[k] for k in ("x", "y", "width", "height", "number", "collide", "damaged", "damageRate")})

# spark skill structure
sp = byn.get("Hitspark 1")
print("Hitspark 1 blocks:")
for b in sp["blocks"]:
    t = b["type"]
    out = {"i": b.get("i"), "wait": b.get("wait"), "x": b.get("x"), "y": b.get("y")}
    if t in ("S", "E", "COM", "V", "Settings"):
        out = {"t": t}
    print("  ", t, out if t == "I" else "")
