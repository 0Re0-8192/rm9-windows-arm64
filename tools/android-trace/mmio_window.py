"""Print every rwmmio event in [t0,t1] of the Android trace, with the virtual page cluster, to reconstruct the pci-msm enable sequence."""
import re
import sys

src, t0, t1 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
pat = re.compile(r"\s(\d+\.\d+): rwmmio_(read|write): (\S+?)\+0x[0-9a-f]+/0x[0-9a-f]+ (?:\[(\S+)\] )?.*?width=(\d+) (?:val=(0x[0-9a-f]+) )?addr=(0x[0-9a-f]+)")
n = 0
for ln in open(src, encoding="utf-8", errors="replace"):
    m = pat.search(ln)
    if not m:
        continue
    t = float(m.group(1))
    if t < t0 or t > t1:
        continue
    n += 1
    print("%.6f %s %-34s %-14s val=%-12s addr=%s" % (t, "W" if m.group(2) == "write" else "R", m.group(3), m.group(4) or "-", m.group(6) or "", m.group(7)))
print("events", n, file=sys.stderr)
