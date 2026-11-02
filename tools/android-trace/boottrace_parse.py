"""Parse an Android boot-time rwmmio ftrace dump (trace4s.txt.gz from android_boottrace_dump.sh).
usage: boottrace_parse.py <trace.gz> [t0 t1] [module-regex]
Prints per caller-module counts in [t0,t1], then the writes of modules matching the regex grouped by virtual 4K page."""
import collections
import gzip
import re
import sys

src = sys.argv[1]
t0 = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
t1 = float(sys.argv[3]) if len(sys.argv) > 3 else 99.0
want = re.compile(sys.argv[4]) if len(sys.argv) > 4 else None
ev = re.compile(r"\s(\d+\.\d+): rwmmio_(write|read): (.*?) -> (.*?) width=(\d+) (?:val=(0x[0-9a-f]+) )?addr=(0x[0-9a-f]+)")


def module_of(s):
    m = re.search(r"\[(\S+)\]", s)
    return m.group(1) if m else ("?raw" if s.startswith("0x") else "vmlinux")


rows = []
op = gzip.open if src.endswith(".gz") else open
for ln in op(src, "rt", errors="replace"):
    m = ev.search(ln)
    if not m:
        continue
    t = float(m.group(1))
    if t < t0 or t > t1:
        continue
    caller, callee = m.group(3).strip(), m.group(4).strip()
    rows.append(dict(t=t, rw=m.group(2)[0].upper(), caller=caller, mod=module_of(caller) if not caller.startswith("0x") else module_of(callee) + "(raw)",
                     w=int(m.group(5)), val=int(m.group(6), 16) if m.group(6) else None, addr=int(m.group(7), 16)))
print(f"events in [{t0},{t1}]: {len(rows)}")
for mod, n in collections.Counter(r["mod"] for r in rows).most_common(40):
    print(f"  {n:7d} {mod}")
if want:
    sel = [r for r in rows if want.search(r["mod"]) or want.search(r["caller"])]
    pages = collections.defaultdict(list)
    for r in sel:
        pages[r["addr"] & ~0xFFF].append(r)
    print(f"\n{len(sel)} events of /{want.pattern}/ in {len(pages)} pages")
    for pg, rs in sorted(pages.items()):
        mods = sorted(set(r["mod"] for r in rs))
        print(f"  page {pg:#x}: {len(rs):5d} ev, t {rs[0]['t']:.4f}..{rs[-1]['t']:.4f}, {','.join(mods)}")
