import re, os, struct

APP = r"C:\Users\RDP\AppData\Local\Temp\1\opencode\fim_extract\app"

def dx(b, n=256, start=0):
    for i in range(start, min(len(b), start+n), 16):
        row = b[i:i+16]
        print(f"{i:04X}  " + " ".join(f"{x:02X}" for x in row).ljust(47) +
              " " + "".join(chr(x) if 32 <= x <= 126 else "." for x in row))

def strings_of(data: bytes, min_len: int = 5):
    return [m.group().decode("latin1") for m in re.finditer(rb'[\x20-\x7e]{%d,}' % min_len, data)]

print("=" * 70)
print("FULL HEADER DUMPS (first 320 bytes)")
print("=" * 70)
for name in ("Aurora.fmx", "Applejack.plx", "Main Menu.dmx", "Mode Select.stx"):
    with open(os.path.join(APP, name), "rb") as f:
        b = f.read(320)
    print(f"--- {name} ---")
    dx(b)
    print()

print("=" * 70)
print("Aurora.exe strings mentioning 2DFM / FM / fmx / plx etc.")
print("=" * 70)
with open(os.path.join(APP, "Aurora.exe"), "rb") as f:
    b = f.read()
pat = re.compile(rb'[\x20-\x7e]{6,}')
hits = []
for m in pat.finditer(b):
    s = m.group().decode("latin1")
    if re.search(r'(2d|d\s?fighter|2dfm|fm2k|fighter\s?maker|fmx|plx|stx|dmx|player|character|project|aeris|ab|cbox|lilith|ikon|enterbrain)', s, re.I):
        hits.append(s)
for h in sorted(set(hits)):
    print("   ", h[:200])

print()
print("First 60 hexdumpable non-art strings of Aurora.exe:")
clean = []
for m in pat.finditer(b):
    s = m.group().decode("latin1")
    letters = sum(c.isalpha() for c in s)
    digits = sum(c.isdigit() for c in s)
    if letters > 5 and digits < letters / 2 and s not in clean:
        clean.append(s)
        if len(clean) >= 60:
            break
for c in clean:
    print("   ", c[:160])
