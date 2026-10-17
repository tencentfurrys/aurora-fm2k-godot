"""Sweep the anchor->ground offset to find FM2K's exact constant."""
import json, os, struct, zlib

ROOT = r"C:\Users\RDP\Documents\Default Project\godot\data"


def read_png(path):
    with open(path, "rb") as f:
        b = f.read()
    pos, w, h, idat = 8, 0, 0, bytearray()
    while pos < len(b):
        ln = struct.unpack_from(">I", b, pos)[0]
        tag = b[pos + 4:pos + 8]
        if tag == b"IHDR":
            w, h, depth, ctype = struct.unpack_from(">IIBB", b, pos + 8)
        elif tag == b"IDAT":
            idat += b[pos + 8:pos + 8 + ln]
        elif tag == b"IEND":
            break
        pos += 12 + ln
    raw = zlib.decompress(bytes(idat))
    stride = w * 4
    out = bytearray(w * h * 4)
    prev = bytearray(stride)
    for y in range(h):
        off = y * (stride + 1)
        ft = raw[off]
        row = bytearray(raw[off + 1:off + 1 + stride])
        if ft == 1:
            for x in range(4, stride):
                row[x] = (row[x] + row[x - 4]) & 0xFF
        elif ft == 2:
            for x in range(stride):
                row[x] = (row[x] + prev[x]) & 0xFF
        elif ft == 3:
            for x in range(stride):
                a = row[x - 4] if x >= 4 else 0
                row[x] = (row[x] + ((a + prev[x]) >> 1)) & 0xFF
        elif ft == 4:
            for x in range(stride):
                a = row[x - 4] if x >= 4 else 0
                c = prev[x - 4] if x >= 4 else 0
                pl = prev[x]
                pa, pb, pc = abs(pl - c), abs(a - c), abs(pl + pc - 2 * c)
                pr = a if pa <= pb and pa <= pc else (pl if pb <= pc else c)
                row[x] = (row[x] + pr) & 0xFF
        prev = row
        out[y * w * 4:(y + 1) * w * 4] = row
    return w, h, bytes(out)


d = json.load(open(os.path.join(ROOT, "characters", "applejack.json")))
immap = {im["id"]: im for im in d["images"]}

cache = {}
def sprite_alpha_mask(fid):
    if fid in cache:
        return cache[fid]
    meta = immap[fid]
    p = os.path.join(ROOT, meta["file"])
    if not os.path.isfile(p):
        cache[fid] = None
        return None
    w, h, rgba = read_png(p)
    mask = [[rgba[(y * w + x) * 4 + 3] > 0 for x in range(w)] for y in range(h)]
    cache[fid] = (w, h, mask)
    return cache[fid]


def box_coverage(rect, fid):
    w, h, mask = sprite_alpha_mask(fid)
    if w is None:
        return None
    x0, y0, bw, bh = rect
    if bw <= 0 or bh <= 0:
        return None
    total = hit = 0
    for yy in range(y0, y0 + bh):
        for xx in range(x0, x0 + bw):
            total += 1
            sx, sy = xx + w // 2, yy + h // 2
            if 0 <= sx < w and 0 <= sy < h and mask[sy][sx]:
                hit += 1
    return hit / total if total else None


samples = []
sk1 = next(s for s in d["skills"] if s["i"] == 1)   # Standing
fr0 = sk1["frames"][0]
samples.append((sk1["boxes"], fr0["i"]))
sk20 = next(s for s in d["skills"] if s["i"] == 20)  # Crouching
if sk20["frames"]:
    samples.append((sk20["boxes"], sk20["frames"][0]["i"]))
sk20b = next((s for s in d["skills"] if s["i"] == 19), None)  # MidCrouch
if sk20b and sk20b["frames"]:
    samples.append((sk20b["boxes"], sk20b["frames"][0]["i"]))

print("ground sweep (convention C: bottom-anchored at ground+by):")
best = None
for g in range(60, 95, 1):
    vals = []
    for boxes, fid in samples:
        for b in boxes:
            bw, bh, bx, by = b["w"], b["h"], b["x"], b["y"]
            c = box_coverage((bx - bw // 2, by + g - bh, bw, bh), fid)
            if c is not None:
                vals.append(c)
    m = sum(vals) / len(vals)
    if best is None or m > best[1]:
        best = (g, m)
    print(f"  ground={g:3d}: {m*100:5.1f}%")
print("BEST:", best)
