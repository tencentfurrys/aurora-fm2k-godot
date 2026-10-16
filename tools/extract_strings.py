"""
Extract printable strings (>= 5 chars) from a binary and grep interesting
engine/system keywords, plus show the context around 'fmx' in Aurora.exe.
"""
import os, re, sys

APP = r"C:\Users\RDP\AppData\Local\Temp\1\opencode\fim_extract\app"

def strings_of(data: bytes, min_len: int = 5):
    return [m.group() for m in re.finditer(rb'[\x20-\x7e]{%d,}' % min_len, data)]

def dump(path: str, min_len: int, keywords: list[bytes], limit: int = 400):
    with open(path, "rb") as f:
        data = f.read()
    s = strings_of(data, min_len)
    print(f">>>> {path} (strings >= {min_len} chars): {len(s)}")
    hits = [x.decode("latin1") for x in s
            if any(k in x for k in keywords)]
    for h in hits[:limit]:
        print("   ", h)
    # context around fmx
    i = 0
    fmxs = []
    for st in s:
        if b"fmx" in st.lower() or b"plx" in st.lower() or b"dmx" in st.lower():
            fmxs.append(st.decode("latin1"))
    print(f"   [fmx/plx/dmx lines: {len(fmxs)}]")
    for x in fmxs[:40]:
        print("    *", x)

KEYWORDS = [
    b"engine", b"Engine", b"ENGINE", b"sdl", b"SDL", b"OpenGL", b"opengl",
    b"DIRECT", b"Direct", b"direct", b"dx", b"DX", b"BITMAP", b"bitmap",
    b"onion", b"Onion", b"hsp", b"HSP", b"hsp3", b"HSP3", b"HGIMG",
    b"lua", b"Lua", b"luaJIT", b"squirrel", b"python", b"PYTHON",
    b"visual", b"Visual", b"borland", b"Borland", b"delphi", b"Delphi",
    b"gcc", b"GCC", b"mingw", b"MINGW", b"msvc", b"MSVC",
    b"aurora", b"Aurora", b"AURORA", b"magic", b"Magic", b"MAGIC",
    b"morningstar", b"Morningstar", b"MORNINGSTAR", b"windowslogic", b"WINDOWSLOGIC",
    b"cupID", b"CUPID", b"cupid", b"exe.exe", b"exebind",
    b"zlib", b"Zlib", b"ZLIB", b"libpng", b"PNG", b"png",
    b"ogg", b"OGG", b"vorbis", b"Vorbis", b"mp3", b"MIDI", b"midi",
    b"netplay", b"Netplay", b"rollback", b"ggpo", b"GGPO",
    b" Fight", b"fight", b"FIGHT", b"Fighting", b"_FREELY",
    b"is_magic", b"IS_MAGIC", b"ismagic", b"#",

]

for tgt in ("Aurora.exe", "MorningStar.exe"):
    print()
    print("=" * 72)
    dump(os.path.join(APP, tgt), min_len=6, keywords=KEYWORDS)
