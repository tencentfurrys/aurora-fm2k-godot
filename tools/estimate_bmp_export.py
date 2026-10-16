import json, os, glob

ROOT = r"C:\Users\RDP\Documents\Default Project\aurora_fm2k"

grand_imgs = 0
grand_px = 0
rows = []
for path in sorted(glob.glob(os.path.join(ROOT, "*.json"))):
    name = os.path.basename(path)[:-5]
    with open(path, "rb") as f:
        d = json.load(f)
    imgs = d.get("images") or []
    px = 0
    n = len(imgs)
    for im in imgs:
        try:
            px += int(im.get("width", 0)) * int(im.get("height", 0))
        except Exception:
            pass
    rows.append((name, n, px))
    grand_imgs += n
    grand_px += px

print(f"{'file':38s} {'images':>7s} {'raw px (MB)':>11s} {'x8 palettes':>12s}")
for name, n, px in sorted(rows, key=lambda r: -r[2])[:30]:
    print(f"{name:38s} {n:7d} {px/1_048_576:11.1f} {(px*8)/1_048_576:12.1f}")
print()
print(f"TOTAL images: {grand_imgs}")
print(f"TOTAL raw pixels: {grand_px/1_048_576:.1f} MB  (x8 palette variants: {grand_px*8/1_048_576:.1f} MB, x1 only: {grand_px/1_048_576:.1f} MB)")
