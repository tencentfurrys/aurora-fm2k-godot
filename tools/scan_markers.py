import re, os, sys

P = r"C:\Users\RDP\Downloads\Fighting is Magic Aurora Setup.exe"

with open(P, 'rb') as f:
    head = f.read(3_000_000)

pat = re.compile(rb'[\x20-\x7e]{5,}')
interesting = []
for m in pat.finditer(head):
    s = m.group().decode('latin1')
    if re.search(r'inno|nullsoft|hsp|aurora|magic|fight|setup|hot\s?soup|\.ax\b|version|copyright', s, re.I):
        interesting.append((m.start(), s[:180]))

print("=== first %d interesting strings in first 3MB ===" % min(120, len(interesting)))
for off, s in interesting[:120]:
    print(off, repr(s))
print("total interesting:", len(interesting))

# whole-file marker counts (streamed)
counts = {b"Inno Setup": 0, b"InnoSetup": 0, b"Nullsoft": 0, b"hsp3": 0, b"HSP3": 0, b"hsp.exe": 0, b".ax\x00": 0}
CHUNK = 8 * 1024 * 1024
size = os.path.getsize(P)
pos = 0
with open(P, 'rb') as f:
    prev_tail = b""
    while True:
        chunk = f.read(CHUNK)
        if not chunk:
            break
        buf = prev_tail + chunk
        for ms in counts:
            counts[ms] += buf.count(ms)
        prev_tail = chunk[-16:]
        pos += len(chunk)
print("=== whole-file marker counts ===")
for k, v in counts.items():
    print(k, "->", v)
print("file size:", size)
