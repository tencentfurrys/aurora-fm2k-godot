import json, os

ROOT = r"C:\Users\RDP\Documents\Default Project\godot\data"
for cname in ("applejack", "rainbow_dash"):
    d = json.load(open(os.path.join(ROOT, "characters", cname + ".json")))
    print("====", cname)
    for c in d["commands"]:
        steps = c.get("steps") or []
        s0 = steps[0] if steps else {}
        btns = [k for k in ("a", "b", "c", "e") if s0.get(k)]
        if len(btns) == 1 and int(s0.get("d", 0)) == 0 and int(s0.get("type", 0)) == 2:
            print(f"  single-press-no-dir: name={c['name']!r} btn={btns[0]} stand={c.get('stand')!r} air={c.get('air')!r} crouch={c.get('crouch')!r}")
    print()
