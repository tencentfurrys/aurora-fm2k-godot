import os

APP = r"C:\Users\RDP\AppData\Local\Temp\1\opencode\fim_extract\app"
path = os.path.join(APP, "Aurora.fmx")
data = open(path, "rb").read(2_000_000)

for magic in (b"FMX1985", b"FMXL0CK", b"PK\x03\x04", b"\x1f\x8b", b"BM", b"RIFX", b"RIFF", b"kgt", b"KGT"):
    print(magic, data.find(magic))

for off in range(0, 4096, 16):
    row = data[off:off + 16]
    if any(row):
        print(f"first nonzero row at 0x{off:06X}: {row[:16].hex()}")
        break
