"""Keep the stock DisplayDxe in the firmware volume but do not dispatch it: depex = FALSE, and no APRIORI entry.  MuChain starts it (\\DISP.TXT).
usage (WSL): python3 patch_display_late.py [on|off]"""
import shutil
import sys
from pathlib import Path

mode = sys.argv[1] if len(sys.argv) > 1 else "on"
dep = Path("/root/Mu-Silicium/Binaries/nx769j/QcomPkg/Drivers/DisplayDxe/DisplayDxe.depex")
dep_o = dep.with_suffix(".depex.rm9orig")
if not dep_o.exists():
    shutil.copy(dep, dep_o)
dep.write_bytes(bytes([0x07, 0x08]) if mode == "on" else dep_o.read_bytes())          # FALSE, END
print("DisplayDxe depex:", "FALSE" if mode == "on" else "original")

ap = Path("/root/Mu-Silicium/Platforms/ZTE/nx769jPkg/Include/APRIORI.inc")
ap_o = ap.with_suffix(".inc.rm9late")
if not ap_o.exists():
    shutil.copy(ap, ap_o)
t = ap_o.read_text(encoding="utf-8")
if mode == "on":
    line = "  INF Binaries/nx769j/QcomPkg/Drivers/DisplayDxe/DisplayDxe.inf"
    assert line in t
    t = t.replace(line, "  # RM9 late display: " + line.strip(), 1)
ap.write_text(t, encoding="utf-8")
print("APRIORI DisplayDxe entry:", "removed" if mode == "on" else "restored")
