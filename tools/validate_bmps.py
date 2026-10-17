import json, struct, os

ROOT = r"C:\Users\RDP\Documents\Default Project\aurora_fm2k"

def check_bmp(rel: str, json_name: str, index: int):
    p = os.path.join(ROOT, rel)
    with open(p, "rb") as f:
        hdr = f.read(34)
    sig, fsize, _, _, _ = struct.unpack("<2sIHHI", hdr[:14])
    w, h, planes, bpp = struct.unpack("<iiHH", hdr[18:30])
    with open(os.path.join(ROOT, json_name), "rb") as f:
        d = json.load(f)
    im = d["images"][index]
    print(f"{rel}: BMP {w}x{h} bpp={bpp}  |  JSON image[{index}]: {im['width']}x{im['height']} "
          f"(match: {w == im['width'] and abs(h) == im['height']})")

# Applejack first three images
for i in range(3):
    check_bmp(os.path.join("Applejack", "img", f"{i:04d}.bmp"), "Applejack.json", i)

# count non-empty image entries per file vs bmp count for Applejack
d = json.load(open(os.path.join(ROOT, "Applejack.json")))
nonempty = sum(1 for im in d["images"] if im.get("width", 0) and im.get("height", 0))
print(f"Applejack JSON non-empty image slots: {nonempty}  (BMPs exported: 562)")
