"""FM2K -> Godot compiler.

Reads the parsed JSON files in aurora_fm2k/, walks every Skill's block list and
compiles it into Godot-friendly JSON:

  frames  : [{i: imageId, x, y, d: frames, fx: flipX, fy: flipY, hold}]
  moves   : [{t: frameIndex, mx, my, add, ...}]    (M blocks)
  sounds  : [{t, s: soundIndex}]                   (S blocks)
  cancels : [{from, to, skill, hits, uncond, ...}] (C blocks)

BMPs referenced by compiled frames are converted to PNG (palette index 0 =
transparent) into godot/data/assets/<slug>/img/, WAVs are copied to snd/.
Only files the game actually executes are converted, keeping the project lean.
"""
import json
import os
import struct
import sys
import zlib

SRC = r"C:\Users\RDP\Documents\Default Project\aurora_fm2k"
OUT = r"C:\Users\RDP\Documents\Default Project\godot\data"

DEF_IMG = 0
DEF_X = 0
DEF_Y = 0


def slugify(name: str) -> str:
    s = name.strip().lower()
    s = s.replace(" ", "_").replace("'", "").replace(".", "").replace("-", "_")
    s = s.replace("(", "").replace(")", "").replace("&", "and")
    return s


# ----------------------------------------------------------------- frame walk
def compile_skill(sk: dict) -> dict:
    frames, moves, sounds, boxes = [], [], [], []
    cur_i, cur_x, cur_y = DEF_IMG, DEF_X, DEF_Y
    cur_fx, cur_fy = False, False
    # state at time of last pushed frame
    last_push_img = None
    cancels = []

    def pin(wait: int, hold: bool = False):
        frames.append({
            "i": cur_i, "x": cur_x, "y": cur_y,
            "d": wait, "fx": cur_fx, "fy": cur_fy,
            "hold": 1 if hold else 0,
        })

    pending_after_push = False  # cur image differs from last pushed frame image
    ti = 0
    reactions = None            # FM2K R block: junction per victim state
    farces = []                 # FM2K FA blocks: attack-force box + power
    for b in sk.get("blocks", []):
        t = b.get("type")
        if t == "I":
            cur_i, cur_x, cur_y = b.get("i", 0), b.get("x", 0), b.get("y", 0)
            cur_fx, cur_fy = bool(b.get("turnX")), bool(b.get("turnY"))
            w = b.get("wait", 0)
            if w > 0:
                pin(w)
                ti += 1
                last_push_img = (cur_i, cur_x, cur_y)
                pending_after_push = False
            else:
                pending_after_push = True
        elif t == "M":
            moves.append({
                "t": ti,
                "mx": b.get("moveX", 0), "my": b.get("moveY", 0),
                "gx": b.get("gravityX", 0), "gy": b.get("gravityY", 0),
                "add": bool(b.get("add")),
                "sx": bool(b.get("stopMoveX")), "sy": bool(b.get("stopMoveY")),
                "sgx": bool(b.get("stopGravityX")), "sgy": bool(b.get("stopGravityY")),
            })
        elif t == "FD":
            boxes.append({
                "t": ti,
                "n": b.get("number", 0),
                "x": b.get("x", 0), "y": b.get("y", 0),
                "w": b.get("width", 0), "h": b.get("height", 0),
                "col": bool(b.get("collide", False)),
                "dmg": bool(b.get("damaged", False)),
                "thr": bool(b.get("throw", False)),
                "rate": int(b.get("damageRate", 100)),
            })
        elif t == "S":
            ref = b.get("sound") or {}
            sounds.append({"t": ti, "s": ref.get("number", 0)})
        elif t == "R":
            if reactions is None:
                reactions = {
                    "hs": (b.get("hitsStand") or {}).get("number", 0),
                    "hc": (b.get("hitsCrouched") or {}).get("number", 0),
                    "ha": (b.get("hitsAir") or {}).get("number", 0),
                    "gs": (b.get("guardStand") or {}).get("number", 0),
                    "gc": (b.get("guardCrouched") or {}).get("number", 0),
                    "ga": (b.get("guardAir") or {}).get("number", 0),
                }
        elif t == "FA":
            farces.append({
                "t": ti,
                "n": b.get("number", 0),
                "x": b.get("x", 0), "y": b.get("y", 0),
                "w": b.get("width", 0), "h": b.get("height", 0),
                "pw": int(b.get("power", 0)),
                "cc": bool(b.get("cancel", False)),
                "cb": bool(b.get("combo", False)),
            })
        elif t == "C":
            ref = b.get("skill") or {}
            cancels.append({
                "from": b.get("from", 0), "to": b.get("to", 0),
                "skill": ref.get("number", 0),
                "hits": bool(b.get("hits")), "uncond": bool(b.get("uncond")),
            })
        # V/E/Settings/FD/DS/O/GL/GS/GP etc. ignored for v0.1

    # trailing pending image (I with wait=0, or zero-frame skill) -> hold frame
    if pending_after_push or not frames:
        pin(1, hold=True)

    return {
        "i": sk.get("index", 0),
        "n": sk.get("name", ""),
        "lvl": (sk.get("settings") or {}).get("level", 0),
        "frames": frames,
        "moves": moves,
        "sounds": sounds,
        "boxes": boxes,
        "farces": farces,
        "reactions": reactions if reactions is not None else {},
        "cancels": cancels,
    }


# ------------------------------------------------------------------- PNG out
def bmp_to_png(bmp: bytes) -> bytes:
    assert bmp[:2] == b"BM"
    pixoff = struct.unpack_from("<I", bmp, 10)[0]
    dib = struct.unpack_from("<I", bmp, 14)[0]
    w = struct.unpack_from("<i", bmp, 18)[0]
    h_signed = struct.unpack_from("<i", bmp, 22)[0]
    bpp = struct.unpack_from("<H", bmp, 28)[0]
    if bpp != 8:
        raise ValueError(f"unsupported bmp bpp {bpp}")
    clrused = struct.unpack_from("<I", bmp, 46)[0]
    n_pal = clrused if clrused in (0,) or clrused > 0 else 0
    n_pal = clrused if clrused else 256
    pal_off = 14 + dib
    pal = []
    for i in range(n_pal):
        bb, g, r, _ = struct.unpack_from("<BBBB", bmp, pal_off + 4 * i)
        pal.append((r, g, bb))
    if len(pal) < 256:
        pal += pal[-1:] * (256 - len(pal))
    rowsize = (w + 3) // 4 * 4
    bottom_up = h_signed > 0
    h = abs(h_signed)
    raw = bytearray()
    rowfifo = []
    for ry in range(h):
        src_row = (h - 1 - ry) if bottom_up else ry
        p = pixoff + src_row * rowsize
        rowfifo.append(bmp[p:p + w])
    for row in rowfifo:
        line = bytearray([0])
        for px in row:
            r, g, b = pal[px][0], pal[px][1], pal[px][2]
            a = 0 if px == 0 else 255
            line += bytes((r, g, b, a))
        raw += line
    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 6)) + chunk(b"IEND", b"")


# ---------------------------------------------------------------- transcoding
def convert_images(imgname: str, used: set, out_dir: str) -> dict:
    srcimg = os.path.join(SRC, imgname, "img")
    outimg = os.path.join(out_dir, "img")
    os.makedirs(outimg, exist_ok=True)
    manifest = {}
    for fid in sorted(used):
        bmp_path = os.path.join(srcimg, f"{fid:04d}.bmp")
        png_name = f"{fid:04d}.png"
        png_path = os.path.join(outimg, png_name)
        if not os.path.isfile(bmp_path):
            continue  # empty image slot in FM2K data
        if not os.path.exists(png_path):
            with open(bmp_path, "rb") as f:
                png = bmp_to_png(f.read())
            with open(png_path, "wb") as f:
                f.write(png)
        with open(png_path, "rb") as f:
            head = f.read(26)
        w, h = struct.unpack(">II", head[16:24])
        rel = os.path.relpath(png_path, OUT).replace(os.sep, "/")
        manifest[fid] = {"w": w, "h": h, "file": rel}
    return manifest


def path_rel(absolute: str) -> str:
    rel = os.path.relpath(absolute, OUT)
    return rel.replace(os.sep, "/").replace("res://data/", "").replace("data/", "", 1)


def copy_sounds(sndname: str, used: set, out_dir: str) -> dict:
    srcsnd = os.path.join(SRC, sndname, "snd")
    outsnd = os.path.join(out_dir, "snd")
    os.makedirs(outsnd, exist_ok=True)
    manifest = {}
    for fid in sorted(used):
        wav_path = os.path.join(srcsnd, f"{fid:04d}.wav")
        if not os.path.exists(wav_path):
            continue
        if os.path.getsize(wav_path) == 0:
            continue
        out_path = os.path.join(outsnd, f"{fid:04d}.wav")
        if not os.path.exists(out_path):
            with open(wav_path, "rb") as f:
                data = f.read()
            with open(out_path, "wb") as f:
                f.write(data)
        rel = os.path.relpath(out_path, OUT).replace(os.sep, "/")
        manifest[fid] = rel
    return manifest


def rel_asset(abs_path: str) -> str:
    return abs_path.replace(OUT + os.sep, "").replace(os.sep, "/").replace("data/", "", 1)


# ------------------------------------------------------------------- commands
## Raw .player command records (82 bytes each, hand-verified against binary):
##   [32  name][u16 time][4x u16 skill refs Air/Stand/StandFar/Crouched]
##   [10 x (flags1, flags2)][10 x u16 window Amount]
## flags1: low nibble = ComDirection (Free0 Point1 Right2 DownRight3 Down4
## DownLeft5 Left6 UpLeft7 Up8 UpRight9, composites 10-13); high 3 bits =
## button id (0=A catch-all, 1=B, 2=C, 3=B+C, 4=D).
## flags2: bit0 = E button, bit4 = Continue (false on the trigger step),
## bit5 = Active. Amount = per-step match window in frames.
## Directions are authored facing-relative (Right = toward the opponent); the
## engine mirrors L<->R at match time per fighter facing.

def decode_raw_command(data: bytes, off: int) -> "dict | None":
    if off + 82 > len(data):
        return None
    rec = data[off:off + 82]
    name = rec[:32].split(b"\x00", 1)[0].decode("ascii", "ignore")
    time_ = int.from_bytes(rec[32:34], "little")
    if time_ == 0 or time_ > 600:
        return None
    ls = [int.from_bytes(rec[34 + i * 2:36 + i * 2], "little") for i in range(4)]
    steps = []
    for i in range(10):
        f1, f2 = rec[42 + i * 2], rec[43 + i * 2]
        if f1 == 0 and (f2 & 0x30) == 0:
            continue  # zero filler row
        if f2 & 0x02:
            # flags2 bit1 marks the deactivated FM2K debug commands
            # (Debug Heal* and friends carry it, no real move does)
            return None
        steps.append({
            "d": f1 & 0x0F,
            "b": f1 >> 5,
            "e": bool(f2 & 1),
            "w": int.from_bytes(rec[62 + i * 2:64 + i * 2], "little"),
            "cont": bool(f2 & 0x10),
        })
        if not bool(f2 & 0x10):
            break                        # trigger row: everything after is junk
    if not steps or not any(not s["cont"] for s in steps):
        return None
    return {
        "n": name,
        "time": time_,
        "ls": {"a": ls[0], "s": ls[1], "sf": ls[2], "c": ls[3]},
        "steps": steps,
    }


def parse_raw_commands(player_path: str, parsed_commands: list) -> list:
    """Decode command records straight from the .player binary (the parser's
    button fields are unreliable - it mislabels the direction nibble)."""
    data = open(player_path, "rb").read()
    out = []
    prev = -1
    for c in parsed_commands:
        name = str(c.get("name") or "")[:32]
        if not name:
            continue
        needle = name.encode("ascii", "ignore")
        rec = None
        pos = len(data)
        while True:  # last valid occurrence wins
            pos = data.rfind(needle, 0, pos)
            if pos < 0:
                break
            cand = decode_raw_command(data, pos)
            if cand and pos > prev:
                rec, prev = cand, pos
                break
        if rec is None:
            print(f"  ! command not decoded: {name!r}")
            continue
        out.append(rec)
    return out


# ------------------------------------------------------------------- compiler
def compile_file(name: str, json_name: str, kind: str) -> dict:
    path = os.path.join(SRC, json_name)
    with open(path, "rb") as f:
        d = json.load(f)

    print(f"encoding PNGs for {name} ...")
    small = []
    for sk in d["skills"]:
        small.append(compile_skill(sk))

    used_imgs = set()
    used_snds = set()
    for sk in small:
        for fr in sk["frames"]:
            used_imgs.add(fr["i"])
        for ev in sk["sounds"]:
            used_snds.add(ev["s"])

    assets_dir = os.path.join(OUT, "assets", slugify(name))
    source_stem = os.path.splitext(json_name)[0]   # resource folder = file stem
    manifest = convert_images(source_stem, used_imgs, assets_dir)
    sndman = copy_sounds(source_stem, used_snds, assets_dir)

    images_out = [{"id": fid, "w": m["w"], "h": m["h"], "file": m["file"]} for fid, m in sorted(manifest.items())]
    sounds_out = [{"id": fid, "file": p} for fid, p in sorted(sndman.items())]

    outd = {
        "name": name,
        "kind": kind,
        "images": images_out,
        "sounds": sounds_out,
        "skills": [sk for sk in small if sk["frames"]],
    }
    if kind == "player":
        outd["builtin"] = d.get("builtInSkills") or {}
        st = d.get("settings") or {}
        outd["settings"] = {
            "life": st.get("lifeGaugeMax", 1000),
            "meter": st.get("specialGaugeMax", 0),
        }
        stem = os.path.splitext(json_name)[0]
        player_path = os.path.join(SRC, stem + ".player")
        if os.path.isfile(player_path):
            outd["commands"] = parse_raw_commands(player_path, d.get("commands") or [])
        else:
            print(f"  ! no .player next to {json_name}; commands skipped")
        outd["junctions"] = [
            {
                "j": (j.get("hitJunction") or {}).get("number", 0),
                "jn": (j.get("hitJunction") or {}).get("name", ""),
                "s": (j.get("spark") or {}).get("number", 0),
                "sn": (j.get("spark") or {}).get("name", ""),
            }
            for j in (d.get("hitJunctionsSkills") or [])
        ]
    return outd


def write_out(name: str, kind: str, obj: dict):
    sub = {"player": "characters", "stage": "stages", "demo": "demos", "kgt": ""}[kind]
    outdir = OUT if kind == "kgt" else os.path.join(OUT, sub)
    os.makedirs(outdir, exist_ok=True)
    outpath = os.path.join(outdir, slugify(name) + ".json")
    with open(outpath, "w", encoding="utf8") as f:
        json.dump(obj, f, separators=(",", ":"))
    print(f"  -> {outpath}  ({os.path.getsize(outpath)/1024:.1f} KB)")


def manifest(chars: list, stages: list):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf8") as f:
        json.dump({"characters": chars, "stages": stages}, f, separators=(",", ":"))
        print("manifest written")


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--all" in args:
        args.remove("--all")

    char_args: list = []
    stage_args: list = []
    mode = "chars"
    for a in args:
        if a == "--stage":
            mode = "stages"
            continue
        if a == "--char":
            mode = "chars"
            continue
        (char_args if mode == "chars" else stage_args).append(a)

    kgt = json.load(open(os.path.join(SRC, "Aurora.json")))
    char_names = list(kgt.get("characters") or [])
    stage_names = list(kgt.get("stages") or [])

    run_chars = char_args if char_args else (char_names if "--all" in sys.argv or not args else ["Applejack", "Rainbow Dash"])
    run_stages = stage_args if stage_args else (["Training Stage", "Sweet Apple Acres"] if "--all" in sys.argv else ["Training Stage"])

    done_chars = []
    for nm in run_chars:
        src_json = nm + ".json"
        if not os.path.exists(os.path.join(SRC, src_json)):
            print(f"skip (no src json): {nm}")
            continue
        obj = compile_file(nm, src_json, "player")
        write_out(nm, "player", obj)
        done_chars.append(nm)

    done_stages = []
    for nm in run_stages:
        src_json = nm + ".json"
        if not os.path.exists(os.path.join(SRC, src_json)):
            print(f"skip (no src json): {nm}")
            continue
        obj = compile_file(nm, src_json, "stage")
        write_out(nm, "stage", obj)
        done_stages.append(nm)

    # KGT common skills (hit sparks, effects, menus) for junction lookups
    if "--no-kgt" not in sys.argv:
        obj = compile_file("KGT", "Aurora.json", "kgt")
        write_out("KGT", "kgt", obj)

    manifest(done_chars, done_stages)
    print("DONE")
