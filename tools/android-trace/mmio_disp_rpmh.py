"""Decode the RPMh requests Android sends while the screen goes OFF and ON: pair each TCS ADDR(+0x38/0x50...) write with the following DATA write,
resolve the address through the cmd-db dump (winboot/cmddb_console.txt)."""
import re

src = r"<RM9_WORKDIR>\winboot\mmio_disp.txt"
db = {}
for ln in open(r"<RM9_WORKDIR>\winboot\cmddb_console.txt", encoding="utf-8", errors="replace"):
    m = re.search(r"CMDDB s\d (\S+)\s+addr=0x([0-9A-Fa-f]+) len=(\d+)", ln)
    if m:
        db[int(m.group(2), 16)] = m.group(1)
pat = re.compile(r"\s(\d+\.\d+): rwmmio_(read|write): (\S+?)\+0x[0-9a-f]+/0x[0-9a-f]+ (?:\[(\S+)\] )?.*?width=(\d+) (?:val=(0x[0-9a-f]+) )?addr=(0x[0-9a-f]+)")
t_off = t_on = None
pend = {}
out = []
for ln in open(src, encoding="utf-8", errors="replace"):
    if "RM9_MARK_SCREEN_OFF" in ln:
        t_off = float(re.search(r"(\d+\.\d+):", ln).group(1))
    if "RM9_MARK_SCREEN_ON" in ln:
        t_on = float(re.search(r"(\d+\.\d+):", ln).group(1))
    m = pat.search(ln)
    if not m or m.group(4) != "qcom_rpmh" or m.group(2) != "write" or m.group(3) != "__tcs_buffer_write":
        continue
    a = int(m.group(7), 16)
    off = a & 0xFFF
    v = int(m.group(6), 16)
    # cmd regs: MSGID 0x34+0x18*n, ADDR 0x38+0x18*n, DATA 0x3c+0x18*n within TCS (base 0xd00 => virtual low bits 0xd34...)
    base = (off - 0xd00) if off >= 0xd00 else off
    rel = (off - 0xd34) % 0x18 if off >= 0xd34 else None
    t = float(m.group(1))
    if rel == 4:
        pend[off] = (t, v)
    elif rel == 8:
        ak = off - 4
        if ak in pend:
            ta, addr = pend.pop(ak)
            name = db.get(addr & ~3, db.get(addr & ~0xFF, "?"))
            ph = "OFF" if (t_off and (t_on is None or t < t_on)) else "ON "
            out.append((t - (t_on or t_off), ph, "0x%05x" % addr, name, "0x%08x" % v))
seen = {}
for r in out:
    print("%8.3f %s %s %-14s %s" % r)
