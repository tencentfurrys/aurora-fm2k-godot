"""Visual proof of the full v0.3 hit sequence using the bridge's exact rules:

  panel: Applejack (right, 'Standing Light' strike frame, fp=1) hits a second
  Applejack (left-facing) at dx=65. Contact zone = FA box ∩ victim belly box.
  Victim shown mid gethit frame ('Hit WK Standin'), spark art (img 608-610)
  drawn centered on the contact point.

  Colors: red FD solid, blue FD hurt/dmg, orange FA force, green throw.
"""
import json, os, struct, zlib

ROOT = r"C:\Users\RDP\Documents\Default Project\godot\data"
OUTP = r"C:\Users\RDP\Documents\Default Project\hit_seq.png"
ANCHOR_UP, CH, CW, GROUND_SCREEN = 88, 240, 480, 200


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
byn = {s["i"]: s for s in d["skills"]}

canvas = bytearray(CW * CH * 4)
for i in range(CW * CH):
    canvas[i * 4:i * 4 + 4] = bytes((150, 170, 190, 255))


def blit(fid, flip, cx, cy):
    w, h, rgba = read_png(os.path.join(ROOT, immap[fid]["file"]))
    ox, oy = int(cx - w // 2), int(cy - h // 2)
    for yy in range(h):
        for xx in range(w):
            p = (yy * w + xx) * 4
            if rgba[p + 3] == 0:
                continue
            sx = (w - 1 - xx) if flip else xx
            qx, qy = ox + sx, oy + yy
            if 0 <= qx < CW and 0 <= qy < CH:
                q = (qy * CW + qx) * 4
                canvas[q:q + 4] = rgba[p:p + 4]


def rect_from(b, mirror, ax):
    lx = (-b["x"] - b["w"] / 2) if mirror else (b["x"] - b["w"] / 2)
    x0 = ax + lx
    y1 = GROUND_SCREEN + b["y"]
    return int(round(x0)), int(round(y1 - b["h"])), b["w"], b["h"]


def draw_box(r, col, fill=True):
    x0, y0, bw, bh = r
    for yy in range(max(0, y0), min(CH, y0 + bh)):
        for xx in range(max(0, x0), min(CW, x0 + bw)):
            edge = xx in (x0, x0 + bw - 1) or yy in (y0, y0 + bh - 1)
            if edge or fill:
                q = (yy * CW + xx) * 4
                canvas[q:q + 4] = bytes(col)


def ground_line(x0, x1):
    for xx in range(x0, x1):
        for dy in (0, -1):
            q = ((GROUND_SCREEN + dy) * CW + xx) * 4
            canvas[q:q + 4] = bytes((90, 70, 50, 255))


AX1, AX2 = 175, 240  # dx = 65 : the regression-test spacing
atk = byn[196]  # Standing Light
victim_std = byn[1]      # Standing
gethit = byn[64]         # 'Hit    WK Standin'

f_atk = atk["frames"][1]   # strike frame
f_vic = victim_std["frames"][0]
f_hit = gethit["frames"][2 if len(gethit["frames"]) > 2 else 0]

ground_line(20, 460)
blit(f_atk["i"], False, AX1 + f_atk["x"], GROUND_SCREEN - ANCHOR_UP + f_atk["y"])
blit(f_vic["i"], True, AX2, GROUND_SCREEN - ANCHOR_UP + f_vic["y"])
blit(f_hit["i"], False, AX2 + f_hit["x"], GROUND_SCREEN - ANCHOR_UP + f_hit["y"])

# boxes at the connect tick
for fd in atk["boxes"]:
    if int(fd["t"]) != 1:
        continue
    r = rect_from(fd, False, AX1)
    draw_box(r, (200, 40, 40) if fd["col"] else (30, 90, 230), fill=False)
for fd in victim_std["boxes"]:
    if int(fd["t"]) != 0:
        continue
    r = rect_from(fd, True, AX2)
    draw_box(r, (30, 90, 230), fill=False)
fa = next(x for x in atk.get("farces", []) if int(x["t"]) == 1 and x["w"] > 0)
r_fa = rect_from(fa, False, AX1)
draw_box(r_fa, (240, 140, 30), fill=False)

# spark frames centered on the FA ∩ trauma overlap center (contact fairness)
fx0 = max(r_fa[0], rect_from(victim_std["boxes"][0], True, AX2)[0])
cx = (r_fa[0] + r_fa[0] + r_fa[2]) // 2
cy = GROUND_SCREEN + fa["y"] - fa["h"] // 2
draw_box((cx - 6, cy - 5, 12, 10), (255, 255, 60), fill=True)
for sid in (608, 609):
    blit(sid, False, cx + 4 * (sid - 608), cy)


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
