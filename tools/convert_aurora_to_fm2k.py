"""Convert Aurora FMXL0CK files to stock FM2K (FMX1985) naming.

Only patches the first 8 bytes (magic). Variant B (separate step) can restore
the 'ISMA' tag at 0x08 if Variant A fails.
"""
import os, sys

APP = r"C:\Users\RDP\AppData\Local\Temp\1\opencode\fim_extract\app"
OUT = r"C:\Users\RDP\Documents\Default Project\aurora_fm2k"
os.makedirs(OUT, exist_ok=True)

MAP = {".plx": ".player", ".stx": ".stage", ".dmx": ".demo", ".fmx": ".kgt"}

def convert(src_name: str, dst_name: str, restore_isma: bool = False):
    with open(os.path.join(APP, src_name), "rb") as f:
        data = bytearray(f.read())
    assert bytes(data[0:8]) == b"FMXL0CK\x00", f"{src_name}: unexpected magic {bytes(data[0:8])!r}"
    data[0:8] = b"FMX1985\x00"
    if restore_isma:
        data[8:12] = b"ISMA"
    with open(os.path.join(OUT, dst_name), "wb") as f:
        f.write(data)
    print(f"{src_name}  ->  {dst_name}  ({len(data):,} bytes)")

if __name__ == "__main__":
    restore = "--isma" in sys.argv
    # single-file mode: convert one specific pair
    if "--one" in sys.argv:
        i = sys.argv.index("--one")
        convert(sys.argv[i + 1], sys.argv[i + 2], restore)
    else:
        out_base = "FightingIsMagic" if "--keep-kgt-name" not in sys.argv else "Aurora"
        for name in os.listdir(APP):
            base, ext = os.path.splitext(name)
            ext = ext.lower()
            if ext in MAP:
                dst = (out_base + MAP[ext]) if ext == ".fmx" else (base + MAP[ext])
                convert(name, dst, restore)
