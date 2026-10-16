import os

REF = r"C:\Users\RDP\Documents\Default Project\ref_dark_chocolate"
APP = r"C:\Users\RDP\AppData\Local\Temp\1\opencode\fim_extract\app"

def hx(b):
    return " ".join(f"{x:02X}" for x in b)

def asc(b):
    return "".join(chr(x) if 32 <= x <= 126 else "." for x in b)

pairs = [
    ("Applejack.player", "Applejack.plx"),
    ("FightingIsMagic.kgt", "Aurora.fmx"),
    ("Canterlot Night.stage", "Canterlot Night.stx"),
    ("Main Menu.demo", "Main Menu.dmx"),
]

for ref_name, aur_name in pairs:
    with open(os.path.join(REF, ref_name), "rb") as f:
        ref = f.read(320)
    with open(os.path.join(APP, aur_name), "rb") as f:
        aur = f.read(320)
    print("=" * 70)
    print(f"{ref_name}  <->  {aur_name}")
    print("=" * 70)
    ndiff = 0
    diffs = []
    for off in range(0, 320, 16):
        r, a = ref[off:off+16], aur[off:off+16]
        if r != a:
            ndiff += 1
            diffs.append(f"DIFF @0x{off:04X}  R {hx(r)} [{asc(r)}]\n                A {hx(a)} [{asc(a)}]")
    print(f"differing 16-byte rows in first 320 bytes: {ndiff}")
    for d in diffs[:12]:
        print("  " + d)
    for tag, buf in (("REF", ref), ("AUR", aur)):
        nz = 0x100
        for i in range(0x100, len(buf)):
            if buf[i]:
                nz = i
                break
        print(f"  {tag} first nonzero byte after 0x100 @0x{nz:04X}")
        s = max(0, nz - 8)
        print("     " + hx(buf[s:nz+48]) + "  [" + asc(buf[s:nz+48]) + "]")
    print()
