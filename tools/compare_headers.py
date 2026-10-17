import os

REF = r"C:\Users\RDP\Documents\Default Project\ref_dark_chocolate"
APP = r"C:\Users\RDP\AppData\Local\Temp\1\opencode\fim_extract\app"

def hex_ascii(b):
    return " ".join(f"{x:02X}" for x in b) + "  " + "".join(chr(x) if 32 <= x <= 126 else "." for x in b)

pairs = [
    ("Applejack.player", "Applejack.plx"),
    ("FightingIsMagic.kgt", "Aurora.fmx"),
    ("Canterlot Night.stage", "Canterlot Night.stx"),
    ("Main Menu.demo", "Main Menu.dmx"),
]

for ref_name, aur_name in pairs:
    print("=" * 72)
    print(f"STOCK {ref_name}  vs  AURORA {aur_name}")
    print("=" * 72)
    with open(os.path.join(REF, ref_name), "rb") as f:
        ref = f.read(320)
    with open(os.path.join(APP, aur_name), "rb") as f:
        aur = f.read(320)
    for off in range(0, 320, 16):
        r = ref[off:off+16]
        a = aur[off:off+16]
        marker = "  <<< DIFFERS" if r != a else ""
        print(f"{off:04X}  R {hex_ascii(r)}{marker}")
        print(f"     A {hex_ascii(a)}")
    print()
