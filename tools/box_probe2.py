"""Render the calibrated FM2K box model on Applejack sprites (visual proof).

Model used by the Godot bridge:
- sprite canvas center sits 88px above the ground line
- FD boxes: bottom edge at box.y above the ground, x centered on the anchor,
  mirrored when the fighter faces left
Colors: red = solid (collide), blue = hurt (damaged), green = throw.
"""
import json, os, struct, zlib

ROOT = r"C:\Users\RDP\Documents\Default Project\godot\data"
OUTP = r"C:\Users\RDP\Documents\Default Project\box_probe.png"
ANCHOR_UP, CH, CW, GROUND_SCREEN = 88, 240, 720, 200


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
byn = {sk["n"]: sk for sk in d["skills"]}

canvas = bytearray(CW * CH * 4)
for i in range(CW * CH):
    canvas[i * 4:i * 4 + 4] = bytes((150, 170, 190, 255))  # sky-ish backdrop


def blit_png(fid, flip, ax, ay):
    w, h, rgba = read_png(os.path.join(ROOT, immap[fid]["file"]))
    ox, oy = ax - w // 2, ay - h // 2
    for yy in range(h):
        for xx in range(w):
            p = (yy * w + xx) * 4
            if rgba[p + 3] == 0:
                continue
            sx = (w - 1 - xx) if flip else xx
            cx, cy = ox + sx, oy + yy
            if 0 <= cx < CW and 0 <= cy < CH:
                q = (cy * CW + cx) * 4
                canvas[q:q + 4] = rgba[p:p + 4]


def draw_boxes(ax, sk, boxes_t, mirror):
    for b in sk["boxes"]:
        if int(b["t"]) not in boxes_t or b["w"] <= 0 or b["h"] <= 0:
            continue
        lx = (-b["x"] - b["w"] / 2) if mirror else (b["x"] - b["w"] / 2)
        x0 = int(round(ax + lx))
        y1 = GROUND_SCREEN + b["y"]
        y0 = int(round(y1 - b["h"]))
        col = (200, 40, 40) if b["col"] else ((40, 90, 230) if b["dmg"] else (30, 160, 40))
        for yy in range(max(0, y0), min(CH, y0 + b["h"])):
            for xx in range(max(0, x0), min(CW, x0 + b["w"])):
                if xx in (x0, x0 + b["w"] - 1) or yy in (y0, y0 + b["h"] - 1):
                    q = (yy * CW + xx) * 4
                    canvas[q:q + 4] = bytes(col)


def ground_line(x0, x1):
    for xx in range(x0, x1):
        for dy in (0, -1):
            q = ((GROUND_SCREEN + dy) * CW + xx) * 4
            canvas[q:q + 4] = bytes((90, 70, 50, 255))


sk_std = byn["Standing"]
sk_lit = byn["Standing Light"]
anchors = [150, 400, 555, 620]

# panel 1: standing with hurt boxes (blue) + solid box (red)
blit_png(sk_std["frames"][0]["i"], False, 150, GROUND_SCREEN - ANCHOR_UP)
ground_line(60, 240)
draw_boxes(150, sk_std, {0}, mirror=False)

# panel 2: light buck on its strike frame (t=1) — blue hurt + red strike
fr1 = sk_lit["frames"][1]
blit_png(fr1["i"], False, 400, GROUND_SCREEN - ANCHOR_UP + fr1["y"])
ground_line(310, 490)
draw_boxes(400, sk_lit, {1}, mirror=False)

# panel 3: match-up at hit distance dx=65, P2 mirrored, boxes on both
fr2 = sk_lit["frames"][0]
blit_png(fr2["i"], False, 555, GROUND_SCREEN - ANCHOR_UP + sk_std["frames"][0]["y"])
blit_png(fr2["i"], True, 620, GROUND_SCREEN - ANCHOR_UP + sk_std["frames"][0]["y"])
ground_line(500, 710)
draw_boxes(555, sk_std, {0}, mirror=False)
draw_boxes(620, sk_std, {0}, mirror=True)


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
