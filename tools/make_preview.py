"""Render a visual proof-sheet: stage bg + several Applejack 'Standing' frames
composited via our own minimal PNG reader/writer (no Pillow needed)."""
import json, os, struct, zlib

ROOT = r"C:\Users\RDP\Documents\Default Project\godot\data"


def read_png(path: str):
    with open(path, "rb") as f:
        b = f.read()
    assert b[:8] == b"\x89PNG\r\n\x1a\n"
    pos, w, h, idat = 8, 0, 0, bytearray()
    while pos < len(b):
        ln = struct.unpack_from(">I", b, pos)[0]
        tag = b[pos + 4:pos + 8]
        if tag == b"IHDR":
            w, h, depth, ctype = struct.unpack_from(">IIBB", b, pos + 8)
            assert depth == 8 and ctype in (6, 2), (depth, ctype)
        elif tag == b"IDAT":
            idat += b[pos + 8:pos + 8 + ln]
        elif tag == b"IEND":
            break
        pos += 12 + ln
    raw = zlib.decompress(bytes(idat))
    stride = w * (4 if ctype == 6 else 3)
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
                pr = a if pa <= pb and pa <= pc else (b0 := 0) or (pl if pb <= pc else c)  # noqa
                pr = a if pa <= pb and pa <= pc else (pl if pb <= pc else c)
                row[x] = (row[x] + pr) & 0xFF
        prev = row
        for x in range(w):
            di = (y * w + x) * 4
            si = x * (4 if ctype == 6 else 3)
            out[di:di + 3] = row[si:si + 3]
            out[di + 3] = row[si + 3] if ctype == 6 else 255
    return w, h, bytes(out)


def write_png(path: str, w: int, h: int, rgb: bytes):
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    raw = bytearray()
    for y in range(h):
        raw += b"\x00" + rgb[y * w * 4:(y + 1) * w * 4]
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))


def blit(canvas: bytearray, cw: int, img: bytes, w: int, h: int, dx: int, dy: int, flip=False):
    for y in range(h):
        cy = dy + y
        if cy < 0 or cy >= 240:
            continue
        for x in range(w):
            sx = (w - 1 - x) if flip else x
            px = (y * w + sx) * 4
            if img[px + 3] == 0:
                continue
            cx = dx + x
            if cx < 0 or cx >= cw:
                continue
            ci = (cy * cw + cx) * 4
            a = img[px + 3] / 255.0
            for k in range(3):
                canvas[ci + k] = int(img[px + k] * a + canvas[ci + k] * (1 - a))


# ---- stage bg (largest image of the stage file) ----
st = json.load(open(os.path.join(ROOT, "stages", "training_stage.json")))
big = max(st["images"], key=lambda im: im["w"] * im["h"])
bw, bh, bimg = read_png(os.path.join(ROOT, big["file"]))

CW, CH = 640, 240
canvas = bytearray(CW * CH * 4)
for i in range(CW * CH):
    canvas[i * 4] = 18
    canvas[i * 4 + 1] = 16
    canvas[i * 4 + 2] = 28

sw, sh = int(bw * 0.75), int(bh * 0.75)
for y in range(sh):
    if y >= CH:
        break
    sy = min(bh - 1, int(y / 0.75))
    for x in range(sw):
        if x >= CW:
            break
        sx = min(bw - 1, int(x / 0.75))
        src = (sy * bw + sx) * 4
        dst = (y * CW + x) * 4
        a = bimg[src + 3] / 255.0
        for k in range(3):
            canvas[dst + k] = int(bimg[src + k] * a + canvas[dst + k] * (1 - a))

# ---- characters: first frames of Standing + one action ----
d = json.load(open(os.path.join(ROOT, "characters", "applejack.json")))
byname = {sk["n"]: sk for sk in d["skills"]}
frames_st = byname["Standing"]["frames"][:9]
frames_fw = byname["Forward"]["frames"][:6]

idx = d["images"]
immap = {im["id"]: im for im in idx}

def cache_png(fid):
    p = os.path.join(ROOT, immap[fid]["file"])
    return read_png(p)

for n, fr in enumerate(frames_st):
    fid = fr["i"]
    if fid not in immap:
        continue
    w, h, img = cache_png(fid)
    s = 0.55
    tw, th = int(w * s), int(h * s)
    dx = 10 + n * 34
    for y in range(th):
        sy = min(h - 1, int(y / s))
        for x in range(tw):
            sx = min(w - 1, int(x / s))
            src = (sy * w + sx) * 4
            if img[src + 3] == 0:
                continue
            dst = ((140 + y) * CW + (dx + x)) * 4
            a = img[src + 3] / 255.0
            for k in range(3):
                canvas[dst + k] = int(img[src + k] * a + canvas[dst + k] * (1 - a))

for n, fr in enumerate(frames_fw):
    fid = fr["i"]
    if fid not in immap:
        continue
    w, h, img = cache_png(fid)
    s = 0.55
    tw, th = int(w * s), int(h * s)
    dx = 640 - 260 + n * 40
    flip = n % 2 == 0
    for y in range(th):
        sy = min(h - 1, int(y / s))
        for x in range(tw):
            sxx = min(w - 1, int(x / s) if not flip else w - 1 - int(x / s))
            src = (sy * w + sxx) * 4
            if img[src + 3] == 0:
                continue
            dst = ((140 + y) * CW + (dx + x)) * 4
            a = img[src + 3] / 255.0
            for k in range(3):
                canvas[dst + k] = int(img[src + k] * a + canvas[dst + k] * (1 - a))

out = os.path.join(os.path.dirname(os.path.dirname(ROOT)), "preview_strip.png")
write_png(out, CW, CH, bytes(canvas))
print("wrote", out)
