import re
from collections import Counter, defaultdict

src = r"<RM9_WORKDIR>\winboot\mmio_disp.txt"
mk = {}
pat = re.compile(r"\s(\d+\.\d+): rwmmio_(read|write): (\S+?)\+0x[0-9a-f]+/0x[0-9a-f]+ (?:\[(\S+)\] )?.*?width=(\d+) (?:val=(0x[0-9a-f]+) )?addr=(0x[0-9a-f]+)")
ev = []
for ln in open(src, encoding="utf-8", errors="replace"):
    if "RM9_MARK" in ln:
        m = re.search(r"(\d+\.\d+):.*(RM9_MARK_\w+)", ln)
        if m:
            mk[m.group(2)] = float(m.group(1))
        continue
    m = pat.search(ln)
    if m:
        ev.append((float(m.group(1)), m.group(2), m.group(3), m.group(4) or "-", m.group(6), m.group(7)))
print(mk, len(ev))
off, on, end = mk["RM9_MARK_SCREEN_OFF"], mk["RM9_MARK_SCREEN_ON"], mk["RM9_MARK_END"]
for name, a, b in (("OFF window", off, on), ("ON window", on, end)):
    c = Counter((e[3], e[1]) for e in ev if a <= e[0] < b)
    print("==", name, "%.3f-%.3f" % (a, b))
    for k, n in c.most_common(25):
        print("  ", n, k)
