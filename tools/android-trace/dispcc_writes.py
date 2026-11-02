"""List the dispcc (regmap_mmio) writes during the Android screen-ON window: offsets relative to the page-aligned cluster base 0xffff8000098a0000."""
import re
import sys

src = r"<RM9_WORKDIR>\winboot\mmio_disp.txt"
BASE = 0xFFFF8000098A0000
tmax = float(sys.argv[1]) if len(sys.argv) > 1 else 0.25
pat = re.compile(r"\s(\d+\.\d+): rwmmio_(read|write): (\S+?)\+0x[0-9a-f]+/0x[0-9a-f]+ (?:\[(\S+)\] )?.*?width=(\d+) (?:val=(0x[0-9a-f]+) )?addr=(0x[0-9a-f]+)")
on = None
last = None
n = 0
for ln in open(src, encoding="utf-8", errors="replace"):
    if "RM9_MARK_SCREEN_ON" in ln:
        on = float(re.search(r"(\d+\.\d+):", ln).group(1))
        continue
    if on is None:
        continue
    m = pat.search(ln)
    if not m or m.group(3) not in ("regmap_mmio_write32le", "regmap_mmio_read32le"):
        continue
    a = int(m.group(7), 16)
    if not (BASE <= a < BASE + 0x20000):
        continue
    t = float(m.group(1)) - on
    if t > tmax:
        break
    if m.group(2) == "write":
        dt = 0 if last is None else (t - last) * 1e6
        last = t
        print("%8.4f +%7.0fus W off=0x%05x val=%s" % (t, dt, a - BASE, m.group(6)))
        n += 1
print("writes:", n, file=sys.stderr)
