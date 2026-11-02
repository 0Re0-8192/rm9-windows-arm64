"""Experiment: do not start SSRDxe (suspected to power down the display subsystem right after its load line).  usage (WSL): python3 patch_no_ssr.py [on|off]"""
import shutil
import sys
from pathlib import Path

mode = sys.argv[1] if len(sys.argv) > 1 else "on"
base = Path("/root/Mu-Silicium/Binaries/nx769j")
for name in ("DXE.inc", "APRIORI.inc"):
    p = base / name
    o = p.with_suffix(p.suffix + ".orig")
    if not o.exists():
        shutil.copy(p, o)
    t = o.read_text(encoding="utf-8")
    if mode == "on":
        n = 0
        out = []
        for ln in t.split("\n"):
            if "Drivers/SSRDxe/SSRDxe.inf" in ln and not ln.lstrip().startswith("#"):
                out.append("# RM9 no-ssr: " + ln)
                n += 1
            else:
                out.append(ln)
        t = "\n".join(out)
        print(name, "commented", n)
    p.write_text(t, encoding="utf-8")
print("no-ssr:", mode)
