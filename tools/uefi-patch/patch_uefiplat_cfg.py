"""uefiplat.cfg tweak: run the stock DisplayDxe panel init synchronously (EnableDisplayThread 1 -> 0).  usage (WSL): python3 patch_uefiplat_cfg.py [0|1]"""
import re
import shutil
import sys
from pathlib import Path

val = sys.argv[1] if len(sys.argv) > 1 else "0"
p = Path("/root/Mu-Silicium/Binaries/nx769j/RawFiles/uefiplat.cfg")
o = p.with_suffix(".cfg.rm9orig")
if not o.exists():
    shutil.copy(p, o)
t = o.read_bytes().decode("utf-8", "replace")
t2, n = re.subn(r"(EnableDisplayThread\s*=\s*0x)\d", r"\g<1>" + val, t)
assert n == 1, n
p.write_bytes(t2.encode("utf-8"))
print("EnableDisplayThread =", val)
