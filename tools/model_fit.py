"""Joint fit of the FM2K ground/anchor model across both chars, all idle frames.

World coordinates: ground = 0, DOWN-positive (FM2K sign convention).
Box region: x in [bx-bw/2, bx+bw/2), y in [by-bh, by)          (bottom-anchored)
Canvas models for the sprite placement at the character anchor:
  CENTER: canvas center at anchor_y = -G
  BOTTOM: canvas bottom at    y   = -B  -> anchor_y = -B - h/2
  TOP:    canvas top at       y   = -T  -> anchor_y = -T + h/2
plus per-frame I-block offset (fx, fy) shifts the canvas center.
Sweeps G/B/T, reports best fit + coverage per model.
"""
import json, os, struct, zlib

ROOT = r"C:\Users\RDP\Documents\Default Project\godot\data"
FAMILIES = ("standing", "forward", "backwrd", "crouching", "midcrouch", "standfromcrouch", "jump", "falling")


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


samples = []
dims = {}
for cname in ("applejack", "rainbow_dash"):
    d = json.load(open(os.path.join(ROOT, "characters", cname + ".json")))
    immap = {im["id"]: im for im in d["images"]}
    built_ids = set(int(v) for v in d["builtin"].values())
    cnt = 0
    for sk in d["skills"]:
        if sk["i"] not in built_ids:
            continue
        n = sk["n"].lower()
        if not any(f in n for f in FAMILIES):
            continue
        for fr in sk["frames"][:8]:
            fid = fr["i"]
            if fid not in immap or fid not in dims:
                if fid not in immap:
                    continue
                p = os.path.join(ROOT, immap[fid]["file"])
                if not os.path.isfile(p):
                    continue
                w, h, rgba = read_png(p)
                matrix = [[rgba[(y * w + x) * 4 + 3] > 0 for x in range(w)] for y in range(h)]
                dims[fid] = (w, h, matrix)
            hurt = [b for b in sk["boxes"] if b["dmg"] and b["w"] > 0 and b["h"] > 0]
            for b in hurt:
                samples.append((b, fid, fr["x"], fr["y"]))
                cnt += 1
    print(f"{cname}: {cnt} hurt-box samples")

def fit(model, off):
    vals = []
    per = {}
    for cname in ("applejack", "rainbow_dash"):
        per[cname] = []
    for b, fid, fx, fy in samples:
        w, h, mask2d = dims[fid]
        if model == "CENTER":
            anchor_y = -off
        elif model == "BOTTOM":
            anchor_y = -off - h / 2
        else:
            anchor_y = -off + h / 2
        canvas_cy = anchor_y + fy
        tot = hit = 0
        for wy in range(b["y"] - b["h"], b["y"]):
            sy = int(round(wy - canvas_cy + h // 2))
            if sy < 0 or sy >= h:
                for wx in range(b["x"] - b["w"] // 2, b["x"] - b["w"] // 2 + b["w"]):
                    tot += 1
                continue
            for wx in range(b["x"] - b["w"] // 2, b["x"] - b["w"] // 2 + b["w"]):
                sx = wx + w // 2
                tot += 1
                if 0 <= sx < w and mask2d[sy][sx]:
                    hit += 1
        if tot:
            vals.append(hit / tot)
    return sum(vals) / len(vals) if vals else 0.0

for model in ("CENTER", "BOTTOM", "TOP"):
    best = None
    for off in range(30, 140, 1):
        m = fit(model, off)
        if best is None or m > best[1]:
            best = (off, m)
    print(f"model {model}: best off={best[0]}  joint coverage={best[1]*100:.1f}%")
