"""RamDebugGuardDxe: accept ENABLE ret=1 ("already enabled", e.g. armed earlier by the SEC patch) instead of resetting Mu.
Idempotent; original saved as RamDebugGuardDxe.c.orig.   usage (WSL): python3 patch_ramguard_tolerate.py [on|off]"""
import shutil
import sys
from pathlib import Path

p = Path("/root/Mu-Silicium/Platforms/ZTE/nx769jPkg/Drivers/RamDebugGuardDxe/RamDebugGuardDxe.c")
o = p.with_suffix(".c.orig")
mode = sys.argv[1] if len(sys.argv) > 1 else "on"
if not o.exists():
    shutil.copy(p, o)
t = o.read_text(encoding="utf-8")
if mode == "on":
    old = '''  DEBUG ((DEBUG_ERROR, "[RAMGUARD] ENABLE ret=%ld\\n", CallStatus));
  if (CallStatus != 0) {'''
    new = '''  DEBUG ((DEBUG_ERROR, "[RAMGUARD] ENABLE ret=%ld\\n", CallStatus));
  if (CallStatus != 0 && CallStatus != 1) {   // RM9: ret=1 = already enabled (armed by SEC)'''
    assert old in t
    t = t.replace(old, new, 1)
p.write_text(t, encoding="utf-8")
print("RamGuard tolerance:", mode)
