"""Mu SimpleFbDxe: point the GOP framebuffer at a free part of the RAM console region (0xD7E40000, 640x680 BGRX) so that whatever
Windows draws (boot logo, spinner, BSOD) is retrievable through the Sahara RAMCON dump.  The panel keeps showing the old splash.
Idempotent; the original file is saved as SimpleFb.c.orig.   usage (WSL):  python3 patch_fb_in_ramcon.py [on|off]"""
import shutil
import sys
from pathlib import Path

p = Path("/root/Mu-Silicium/Silicon/Silicium/SiliciumPkg/Drivers/SimpleFbDxe/SimpleFb.c")
o = p.with_suffix(".c.orig")
mode = sys.argv[1] if len(sys.argv) > 1 else "on"
if not o.exists():
    shutil.copy(p, o)
t = o.read_text(encoding="utf-8")
if mode == "on":
    old = "  // Pass Frame Buffer Address\n  *BaseAddress = FrameBufferRegion.Address;\n"
    assert old in t
    new = ("  // Pass Frame Buffer Address\n  *BaseAddress = FrameBufferRegion.Address;\n"
           "  // RM9: framebuffer inside the RAM console region so a post-crash dump contains the screen\n"
           "  *BaseAddress = 0xD7E40000ULL;\n  *Width = 640;\n  *Height = 680;\n")
    t = t.replace(old, new, 1)
p.write_text(t, encoding="utf-8")
print("framebuffer redirect:", mode)
