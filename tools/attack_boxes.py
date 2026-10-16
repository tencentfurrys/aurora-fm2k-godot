import json, os

ROOT = r"C:\Users\RDP\Documents\Default Project\godot\data"
for cname in ("applejack", "rainbow_dash"):
    d = json.load(open(os.path.join(ROOT, "characters", cname + ".json")))
    byn = {sk["n"]: sk for sk in d["skills"]}
    print("====", cname)
    # first few button commands matched at runtime
    got = 0
    for c in d["commands"]:
        steps = c.get("steps") or []
        if not steps or int(steps[0].get("d", 0)) != 0:
            continue
        cnt = sum(1 for k in ("a", "b", "c", "e") if steps[0].get(k))
        if cnt != 1:
            continue
        tgt = c.get("stand")
        if not tgt or tgt not in byn:
            continue
        sk = byn[tgt]
        boxes = sk.get("boxes", [])
        if not boxes:
            continue
        print(f"  command {c['name']!r} -> skill {sk['i']} {sk['n']!r} lvl={sk['lvl']} frames={len(sk['frames'])}")
        for b in boxes:
            print(f"    t={b['t']:3d} slot={b['n']:2d} x={b['x']:5d} y={b['y']:5d} w={b['w']:4d} h={b['h']:4d} col={int(b['col'])} dmg={int(b['dmg'])} thr={int(b['thr'])} rate={b['rate']}")
        frames = sk["frames"]
        tot = sum(f["d"] for f in frames if not f.get("hold"))
        print(f"    total anim ticks ~ {tot}")
        got += 1
        if got >= 3:
            break
