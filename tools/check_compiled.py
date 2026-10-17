import json

d = json.load(open(r"C:\Users\RDP\Documents\Default Project\godot\data\characters\applejack.json"))
print("skills:", len(d["skills"]))
byn = {}
for sk in d["skills"]:
    byn.setdefault(sk["n"], sk)
for nm in ("Standing", "Forward", "Backwrd", "Crouching", "Jump Up"):
    sk = byn.get(nm)
    if not sk:
        print(nm, "-> MISSING")
        continue
    fs = sk["frames"]
    first3 = [(f["i"], f["x"], f["y"], f["d"]) for f in fs[:3]]
    print(f"{nm!r}: idx={sk['i']} frames={len(fs)} first3={first3} sounds={sk['sounds'][:3]} moves={sk['moves'][:1]}")

bi = d["builtin"]
print("builtin standing idx:", bi["standing"])
# image manifest size
print("images in manifest:", len(d["images"]), " sounds:", len(d["sounds"]))
