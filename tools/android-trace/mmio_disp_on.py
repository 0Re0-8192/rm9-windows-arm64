"""List the start of the Android screen-ON sequence: first N non-frame events with callers (power/clock/gdsc/rpmh votes before MDP programming)."""
import re
import sys

src = r"<RM9_WORKDIR>\winboot\mmio_disp.txt"
n_max = int(sys.argv[1]) if len(sys.argv) > 1 else 400
skip_mod = set(sys.argv[2].split(",")) if len(sys.argv) > 2 else set()
pat = re.compile(r"\s(\d+\.\d+): rwmmio_(read|write): (\S+?)\+0x[0-9a-f]+/0x[0-9a-f]+ (?:\[(\S+)\] )?.*?width=(\d+) (?:val=(0x[0-9a-f]+) )?addr=(0x[0-9a-f]+)")
on = None
rows = []
for ln in open(src, encoding="utf-8", errors="replace"):
    if "RM9_MARK_SCREEN_ON" in ln:
        on = float(re.search(r"(\d+\.\d+):", ln).group(1))
        continue
    if on is None:
        continue
    m = pat.search(ln)
    if not m:
        continue
    mod = m.group(4) or "-"
    if mod in skip_mod:
        continue
    rows.append((float(m.group(1)) - on, m.group(2)[0].upper(), m.group(3), mod, m.group(6) or "", m.group(7)))
    if len(rows) >= n_max:
        break
for r in rows:
    print("%8.4f %s %-36s %-12s val=%-12s addr=%s" % r)
