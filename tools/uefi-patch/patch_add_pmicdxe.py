"""Add Qualcomm's stock PmicDxeLa (PMIC GPIO/NPA client protocols the stock DisplayDxe/ButtonsDxe/UsbConfigDxe need) right after SPMIDxe in the nx769j
platform driver lists.   usage (WSL): python3 patch_add_pmicdxe.py [on|off]"""
import shutil
import sys
from pathlib import Path

mode = sys.argv[1] if len(sys.argv) > 1 else "on"
base = Path("/root/Mu-Silicium/Platforms/ZTE/nx769jPkg/Include")
line = "  INF Binaries/nx769j/QcomPkg/Drivers/PmicDxe/PmicDxeLa.inf"
anchor = "  INF Binaries/nx769j/QcomPkg/Drivers/SPMIDxe/SPMIDxe.inf"
for name in ("DXE.inc", "APRIORI.inc"):
    p = base / name
    o = p.with_suffix(p.suffix + ".rm9orig")
    if not o.exists():
        shutil.copy(p, o)
    t = o.read_text(encoding="utf-8")
    if mode == "on":
        assert anchor in t, name
        t = t.replace(anchor, anchor + "\n" + line, 1)
    p.write_text(t, encoding="utf-8")
    print(name, mode)
