"""ConfigurationMapLib: EnableDisplayThread 1 -> 0 for nx769j (run the stock display init synchronously).   usage (WSL): python3 patch_displaythread_map.py [0|1]"""
import shutil
import sys
from pathlib import Path

val = sys.argv[1] if len(sys.argv) > 1 else "0"
p = Path("/root/Mu-Silicium/Platforms/ZTE/nx769jPkg/Library/ConfigurationMapLib/ConfigurationMapLib.c")
o = p.with_suffix(".c.rm9orig")
if not o.exists():
    shutil.copy(p, o)
t = o.read_text(encoding="utf-8")
old = '{"EnableDisplayThread", 0x1}'
assert old in t
p.write_text(t.replace(old, '{"EnableDisplayThread", %s}' % val), encoding="utf-8")
print("EnableDisplayThread =", val)
