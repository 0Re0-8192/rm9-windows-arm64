"""SiliciumPkg.dsc.inc: raise the DEBUG print mask for the DEBUG build so DisplayDxe's DEBUG_INFO traces appear.  usage (WSL): python3 patch_debuglevel.py [on|off]"""
import shutil
import sys
from pathlib import Path

mode = sys.argv[1] if len(sys.argv) > 1 else "on"
p = Path("/root/Mu-Silicium/Silicon/Silicium/SiliciumPkg/SiliciumPkg.dsc.inc")
o = p.with_suffix(".inc.rm9orig")
if not o.exists():
    shutil.copy(p, o)
t = o.read_text(encoding="utf-8")
old = "gEfiMdePkgTokenSpaceGuid.PcdDebugPrintErrorLevel|0x8007EE0F"
assert old in t
if mode == "on":
    t = t.replace(old, "gEfiMdePkgTokenSpaceGuid.PcdDebugPrintErrorLevel|0x8007EE6F", 1)
p.write_text(t, encoding="utf-8")
print("debug level", mode)
