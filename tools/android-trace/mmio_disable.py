import re
import sys

src = r"<RM9_WORKDIR>\winboot\mmio_win.txt"
t0, t1 = float(sys.argv[1]), float(sys.argv[2])
want = sys.argv[3] if len(sys.argv) > 3 else "pci_msm_drv|pinctrl_msm|cnss2"
pat = re.compile(r"\s(\d+\.\d+): rwmmio_(read|write): (\S+?)\+0x[0-9a-f]+/0x[0-9a-f]+ (?:\[(\S+)\] )?.*?width=(\d+) (?:val=(0x[0-9a-f]+) )?addr=(0x[0-9a-f]+)")
for ln in open(src, encoding="utf-8", errors="replace"):
    m = pat.search(ln)
    if not m:
        continue
    t = float(m.group(1))
    if t < t0 or t > t1:
        continue
    mod = m.group(4) or "-"
    if re.search(want, mod) and m.group(2) == "write":
        print("%.6f W %-30s %-14s val=%-12s addr=%s" % (t, m.group(3), mod, m.group(6) or "", m.group(7)))
