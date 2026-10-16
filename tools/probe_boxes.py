import json

# RAW parser output (keys: index/name/settings/blocks)
d = json.load(open(r"C:\Users\RDP\Documents\Default Project\aurora_fm2k\Applejack.json"))

print("=== Applejack skill 1 'Standing' blocks (looking for FD hurt boxes) ===")
sk = d["skills"][1]
print("name:", sk["name"])
for b in sk["blocks"]:
    if b.get("type") in ("FD", "Settings"):
        print("  ", {k: v for k, v in b.items() if k != "data"})

print()
print("=== attack skill settings levels (skill 5 Dash Forward, skill 6?) ===")
for sk in d["skills"][5:9]:
    st = sk.get("settings") or {}
    types = [b.get("type") for b in sk["blocks"]]
    print(f"skill {sk['index']} {sk['name']!r} settings.level={st.get('level')} settingsType={st.get('settingsType')} FDs={types.count('FD')}")

print()
print("=== junction skill 64 in KGT (hit reaction) ===")
k = json.load(open(r"C:\Users\RDP\Documents\Default Project\aurora_fm2k\Aurora.json"))
j = k["skills"][64]
print("name:", j["name"])
print("settings:", j.get("settings"))
for b in j["blocks"][:10]:
    print("  ", {k2: v for k2, v in b.items() if k2 != "data"})
print("junction list len:", len(d.get("hitJunctionsSkills") or []))
