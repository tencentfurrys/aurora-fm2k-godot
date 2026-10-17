import json, os

ROOT = r"C:\Users\RDP\Documents\Default Project\godot\data"
d = json.load(open(os.path.join(ROOT, "characters", "applejack.json")))
byname = {sk["n"]: sk for sk in d["skills"]}
for c in d["commands"]:
    steps = c.get("steps") or []
    ss = []
    for s in steps:
        btns = "".join(k for k in ("a", "b", "c", "e") if s.get(k)) or "-"
        ss.append(f"[d{s.get('d')} t{s.get('type')} am{s.get('amount')} {btns}]")
        if len(ss) > 4:
            break
    tgt = c.get("stand") or ""
    lvl = byname.get(tgt, {}).get("lvl", "")
    print(f"{c['name'][:34]:34s} {' '.join(ss):52s} -> {tgt} (lvl {lvl})")
