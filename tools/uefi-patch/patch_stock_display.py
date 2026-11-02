"""Switch the nx769j build from Mu's SimpleFbDxe to Qualcomm's stock DisplayDxe (+ panel XMLs): USE_CUSTOM_DISPLAY_DRIVER 0 -> 1.   usage (WSL): python3 patch_stock_display.py [1|0]"""
import re
import shutil
import sys
from pathlib import Path

val = sys.argv[1] if len(sys.argv) > 1 else "1"
p = Path("/root/Mu-Silicium/Platforms/ZTE/nx769jPkg/nx769j.dsc")
o = p.with_suffix(".dsc.orig")
if not o.exists():
    shutil.copy(p, o)
t = o.read_text(encoding="utf-8")
t2, n = re.subn(r"(USE_CUSTOM_DISPLAY_DRIVER\s*=\s*)\d", r"\g<1>" + val, t)
assert n == 1, n
p.write_text(t2, encoding="utf-8")
print("USE_CUSTOM_DISPLAY_DRIVER =", val)
