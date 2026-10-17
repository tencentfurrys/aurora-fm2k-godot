import json, os

ROOT = r"C:\Users\RDP\Documents\Default Project\godot\data"
for cname in ("applejack",):
    d = json.load(open(os.path.join(ROOT, "characters", cname + ".json")))
    byn = {sk["n"]: sk for sk in d["skills"]}
    print("====", cname, "commands:\n")
    for c in d["commands"][:20]:
        steps = c.get("steps") or []
        s0 = steps[0] if steps else None
        tgt = c.get("stand")
        print(f"name={c['name']!r}")
        print(f"   steps0={s0}")
        print(f"   stand={tgt!r} exists={tgt in byn}")
