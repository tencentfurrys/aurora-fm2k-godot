"""Render Applejack's standing sprite with FD hurt/push boxes under three
candidate coordinate conventions to find the right one empirically."""
import json, os, struct, zlib

ROOT = r"C:\Users\RDP\Documents\Default Project\godot\data"
OUTP = r"C:\Users\RDP\Documents\Default Project\box_probe.png"


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
sk1 = next(s for s in d["skills"] if s["i"] == 1)
fr0 = sk1["frames"][0]
w, h, img = read_png(os.path.join(ROOT, immap[fr0["i"]]["file"]))
boxes = sk1["boxes"]
print("standing frame img:", fr0["i"], "size", w, h)
print("boxes:", boxes)

CW, CH = 640, 360
canvas = bytearray(CW * CH * 4)
for i in range(CW * CH):
    canvas[i * 4:i * 4 + 4] = bytes((255, 255, 255, 255))

def blit(dx, dy):
    ox, oy = dx - w // 2, dy - h // 2
    for yy in range(h):
        for xx in range(w):
            p = (yy * w + xx) * 4
            if img[p + 3] == 0:
                continue
            cx, cy = ox + xx, oy + yy
            if 0 <= cx < CW and 0 <= cy < CH:
                q = (cy * CW + cx) * 4
                canvas[q:q + 4] = img[p:p + 4]

def rect(cx0, cy0, bw, bh, col):
    for yy in range(max(0, cy0), min(CH, cy0 + bh)):
        for xx in range(max(0, cx0), min(CW, cx0 + bw)):
            edge = xx in (cx0, cx0 + bw - 1) or yy in (cy0, cy0 + bh - 1)
            if edge:
                q = (yy * CW + xx) * 4
                canvas[q:q + 4] = bytes(col)

# ground line at GY below anchor; anchor at (160, 120) per column
GY = 75
for col in range(3):
    ax = 105 + col * 215
    ay = 130
    blit(ax, ay)
    # draw ground line
    for xx in range(ax - 90, ax + 90):
        if 0 <= xx < CW:
            q = ((ay + GY) * CW + xx) * 4
            canvas[q:q + 4] = bytes((0, 0, 0, 255))
    for b in boxes:
        bx, by, bw2, bh2 = b["x"], b["y"], b["w"], b["h"]
        if col == 0:   # A: anchor-center convention
            x0, y0 = ax + bx - bw2 // 2, ay + by - bh2 // 2
        elif col == 1:  # B: ground-shifted center convention
            x0, y0 = ax + bx - bw2 // 2, ay + GY + by - bh2 // 2
        else:           # C: ground-shifted bottom-anchored
            x0 = ax + bx - bw2 // 2
            y1 = ay + GY + by
            y0 = y1 - bh2
        color = (255, 0, 0) if b["col"] else ((0, 160, 255) if b["dmg"] else (0, 200, 0))
        rect(x0, y0, bw2, bh2, color)

def chunk(tag, data):
    c = tag + data
    return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

ihdr = struct.pack(">IIBBBBB", CW, CH, 8, 6, 0, 0, 0)
raw = bytearray()
for y in range(CH):
    raw += b"\x00" + canvas[y * CW * 4:(y + 1) * CW * 4]
with open(OUTP, "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b""))
print("wrote", OUTP)
