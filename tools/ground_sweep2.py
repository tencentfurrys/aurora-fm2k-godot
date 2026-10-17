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


for cname in ("applejack", "rainbow_dash"):
    d = json.load(open(os.path.join(ROOT, "characters", cname + ".json")))
    immap = {im["id"]: im for im in d["images"]}
    bi = d["builtin"]
    sk = next(s for s in d["skills"] if s["i"] == int(bi["standing"]))
    fid = next(fr["i"] for fr in sk["frames"] if fr["i"] in immap)
    w, h, rgba = read_png(os.path.join(ROOT, immap[fid]["file"]))
    mask = [[rgba[(y * w + x) * 4 + 3] > 0 for x in range(w)] for y in range(h)]
    print(cname, "standing img", fid, "size", w, h)
    best = None
    for g in range(55, 100):
        vals = []
        for b in sk["boxes"]:
            bw, bh, bx, by = b["w"], b["h"], b["x"], b["y"]
            if bw <= 0 or bh <= 0:
                continue
            tot = hit = 0
            for yy in range(by + g - bh, by + g):
                for xx in range(bx - bw // 2, bx - bw // 2 + bw):
                    tot += 1
                    sx, sy = xx + w // 2, yy + h // 2
                    if 0 <= sx < w and 0 <= sy < h and mask[sy][sx]:
                        hit += 1
            if tot:
                vals.append(hit / tot)
        if vals:
            m = sum(vals) / len(vals)
            if best is None or m > best[1]:
                best = (g, m)
    print("  BEST ground offset:", best[0], f"{best[1]*100:.1f}%")
