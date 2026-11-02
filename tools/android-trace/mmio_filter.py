"""Filter the Android ftrace rwmmio capture down to the pci-msm driver and print it compactly: time, R/W, caller, width, val, addr."""
import re
import sys

src = sys.argv[1] if len(sys.argv) > 1 else r"<RM9_WORKDIR>\winboot\mmio_pcie.txt"
pat = re.compile(r"\] [.a-zA-Z]+\s+([0-9.]+): rwmmio_(read|write|post_read|post_write): (\S+) .*?width=(\d+) (?:val|value)=(0x[0-9a-f]+|\d+) addr=(0x[0-9a-f]+)")
rows = []
other = 0
for ln in open(src, encoding="utf-8", errors="replace"):
    if not re.search(r"msm_pcie|pcie_phy|pci_msm|pcie_", ln):
        continue
    m = re.search(r"([0-9]+\.[0-9]+): rwmmio_(\w+): (\S+)", ln)
    if not m:
        other += 1
        continue
    w = re.search(r"width=(\d+)", ln)
    v = re.search(r"val=(0x[0-9a-f]+)", ln)
    a = re.search(r"addr=(0x[0-9a-f]+)", ln)
    rows.append((float(m.group(1)), m.group(2), m.group(3), w.group(1) if w else "?", v.group(1) if v else "?", a.group(1) if a else "?"))
print("rows", len(rows), "unparsed", other)
mode = sys.argv[2] if len(sys.argv) > 2 else "summary"
if mode == "summary":
    from collections import Counter
    c = Counter((r[2].split("+")[0], r[1]) for r in rows)
    for k, n in c.most_common(40):
        print(n, k)
    hi = Counter((int(r[5], 16) >> 12) << 12 if r[5] != "?" else 0 for r in rows)
    print("page clusters (virtual):")
    for k, n in sorted(hi.items())[:60]:
        print(hex(k), n)
else:
    for r in rows:
        print("%.6f %-10s %-40s w=%s val=%s addr=%s" % r)
