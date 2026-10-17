"""Empirically determine FM2K FD-box coordinate convention by measuring how
well hurt/push boxes overlap opaque sprite pixels under each candidate
interpretation."""
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
    if not os.path.isfile(os.path.join(ROOT, meta["file"])):
        cache[fid] = None
        return None
    w, h, rgba = read_png(os.path.join(ROOT, meta["file"]))
    mask = [[rgba[(y * w + x) * 4 + 3] > 0 for x in range(w)] for y in range(h)]
    cache[fid] = (w, h, mask)
    return cache[fid]


def box_coverage(rect, fid, fx, fy):
    """fraction of rect pixels inside the sprite's opaque area"""
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
            sx, sy = xx + w // 2, yy + h // 2   # sprite centered on the anchor
            # account for the I-block offset of this frame
            sx -= fx
            sy -= fy
            if 0 <= sx < w and 0 <= sy < h and mask[sy][sx]:
                hit += 1
    return hit / total if total else None


# skills that idle/walk/crouch/jump = body-hugging hurt + push boxes only
SYS_SKILLS = {"Standing", "Forward", "Backwrd", "Crouching", "Jump Up", "Jump", "falling", "Falling", "dash"}
results = {k: [] for k in "ABCDEF"}
sk_used = 0
for sk in d["skills"]:
    name = sk["n"].lower()
    if not any(s in name for s in ("standing", "forward", "backwrd", "crouching", "jump", "falling")):
        continue
    hurt_push = [b for b in sk["boxes"] if (b["dmg"] or (b["col"] and not sk["boxes"][:1])) and b["w"] > 0 and b["h"] > 0]
    # only boxes of idling skills (attack boxes differ anyway)
    if not ("standing" in name or "crouching" in name or "jump" in name or "falling" in name or "forward" in name or "backwrd" in name):
        continue
    for fr in sk["frames"][:6]:
        fid = fr["i"]
        if fid not in immap:
            continue
        if sprite_alpha_mask(fid) is None:
            continue
        fx, fy = fr["x"], fr["y"]
        for b in hurt_push:
            bw, bh, bx, by = b["w"], b["h"], b["x"], b["y"]
            ground = 75  # hands: anchor->ground offset guess
            cands = {
                "A": (bx - bw // 2, by - bh // 2, bw, bh),                    # center @ anchor
                "B": (bx - bw // 2, by + ground - bh // 2, bw, bh),           # center @ ground-shifted
                "C": (bx - bw // 2, by + ground - bh, bw, bh),                # bottom @ ground-shifted
                "D": (bx - bw // 2, by - bh, bw, bh),                        # bottom @ anchor (up-negative)
                "E": (bx - bw // 2, -by - bh // 2, bw, bh),                  # center, y flipped
                "F": (bx - bw // 2, -by + ground - bh // 2, bw, bh),         # center ground-shifted, y flipped
            }
            for k, r in cands.items():
                c = box_coverage(r, fid, fx, fy)
                if c is not None:
                    results[k].append((c, sk["n"], b["n"]))

sk_used += 1
print(f"evaluated {sk_used} skill(s)")
for k in "ABCDEF":
    vals = results[k]
    if not vals:
        print(k, "no data")
        continue
    m = sum(v[0] for v in vals) / len(vals)
    print(f"conv {k}: mean coverage {m*100:5.1f}%  ({len(vals)} boxes)")
