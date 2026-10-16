import json, os

SRCA = r"C:\Users\RDP\Documents\Default Project\aurora_fm2k"
SRCG = r"C:\Users\RDP\Documents\Default Project\godot\data"

# 1) raw player: junction skill refs player.skills list
d = json.load(open(os.path.join(SRCA, "Applejack.json")))
sk = d["skills"]
print("raw player skills:", len(sk))
for i in (64, 85, 182, 183, 184):
    s = sk[i]
    print(f"  player.skills[{i}] = {s['name']!r}  blocks={len(s['blocks'])}")

# 2) junction table head
hjs = d["hitJunctionsSkills"]
print("junctions entries:", len(hjs))
for i in range(0, 26):
    h = hjs[i]
    hj = h["hitJunction"]
    sp = h["spark"]
    print(f"  j[{i:3d}] junction#{hj['number']:3d} name={hj['name'][:28]!r:32} spark#{sp['number']:3d}")

# 3) R blocks present in raw player skill blocks?
types = {}
rskills = []
for s in sk:
    for b in s["blocks"]:
        t = b["type"]
        types[t] = types.get(t, 0) + 1
        if t == "R":
            rskills.append(s["index"])
print("raw block type histogram:", types)
print("skills with R blocks:", len(rskills), "first few:", rskills[:8])

if rskills:
    for i in rskills[:4]:
        s = sk[i]
        for b in s["blocks"]:
            if b["type"] == "R":
                print(f"  skill {i} {s['name'][:28]!r} R: hitStand={b['hitsStand']} hitCrouch={b['hitsCrouched']} hitAir={b['hitsAir']} guardStand={b['guardStand']}")

# 4) compiled data quick check
cd = json.load(open(os.path.join(SRCG, "characters", "applejack.json")))
compiled_names = {s["i"]: s["n"] for s in cd["skills"]}
print("compiled skills:", len(compiled_names))
for i in (64, 85, 182):
    print(f"  compiled [{i}] has:", compiled_names.get(i, "MISSING"))
