"""Binary patch of the stock DisplayDxe.efi: ignore a missing PMIC NPA client (the PMIC protocol stack is not in this Mu image; the panel supplies are
already up from the bootloader).  NOP the failure branch after npa client creation and the NPA request/complete calls that would use the NULL handle.
usage (WSL): python3 patch_displaydxe_npa.py [on|off]"""
import shutil
import struct
import sys
from pathlib import Path

mode = sys.argv[1] if len(sys.argv) > 1 else "on"
p = Path("/root/Mu-Silicium/Binaries/nx769j/QcomPkg/Drivers/DisplayDxe/DisplayDxe.efi")
o = p.with_suffix(".efi.rm9orig")
if not o.exists():
    shutil.copy(p, o)
d = bytearray(o.read_bytes())
NOP = 0xD503201F
sites = [
    (0x4478, "cbz", 0),    # cbz x0, fail  (client creation returned NULL)
    (0x5204, "bl", None),  # bl npa request wrapper with NULL handle
    (0x526c, "cbz", 8),    # cbz x8, 'NULL Handle' error
    (0x53bc, "bl", None),  # bl npa complete wrapper with NULL handle
]
def b_imm(src, dst):
    return 0x14000000 | (((dst - src) // 4) & 0x3FFFFFF)


# (offset, expected kind/reg, replacement word)
extra = [
    (0x515C, "cbz", 0, b_imm(0x515C, 0x5190)),   # PMIC GPIO protocol locate failed -> continue as if present
    (0x52CC, "cbz", 0, b_imm(0x52CC, 0x52FC)),   # same, in the vote function
    (0x776C, "bl", None, 0x2A1F03E0),            # skip the panel init command list (bl 0x7870 -> mov w0,wzr): the panel is already up from the bootloader and its DSI byte clock is not running here
    (0x7790, "bl", None, NOP),                   # bl 0x7b44 (panel on/mode DCS commands) -> same reasoning
    (0x99D0, "bl", None, NOP),                   # DSI cmd DMA: wait for the 'done' event (needs the display interrupt, which Mu does not route) -> rely on the poll after it
    (0x1A550, "bne", None, b_imm(0x1A550, 0x1A558)),   # delay helper: always the plain Stall path (the other one sleeps on a thread/timer protocol)
    (0x2880, "bl", None, NOP),                   # SetMode display loop: bl 0x144c0(w1=0, backlight level) hangs (backlight/DCS path) -> skip, panel brightness is already set by the bootloader
    (0x5364, "ldr", None, NOP),                # ldr x8,[x8,#8]  (x8 = NULL protocol)
    (0x5368, "blr", None, NOP),                  # blr x8          (PmicGpio->Configure)
]
if mode == "on":
    for off, kind, reg, new in extra:
        w = struct.unpack_from("<I", d, off)[0]
        if kind == "cbz":
            assert (w & 0xFF000000) in (0xB4000000, 0x34000000) and (w & 31) == reg, (hex(off), hex(w))
        elif kind == "bne":
            assert (w & 0xFF00001F) == 0x54000001, (hex(off), hex(w))
        elif kind == "bl":
            assert (w & 0xFC000000) == 0x94000000, (hex(off), hex(w))
        elif kind == "ldr":
            assert (w & 0xFFC00000) == 0xF9400000, (hex(off), hex(w))
        else:
            assert (w & 0xFFFFFC1F) == 0xD63F0000, (hex(off), hex(w))
        struct.pack_into("<I", d, off, new)
        print("patched %#x (%s was %#010x -> %#010x)" % (off, kind, w, new))
    for off, kind, reg in sites:
        w = struct.unpack_from("<I", d, off)[0]
        if kind == "cbz":
            assert (w & 0xFF000000) in (0xB4000000, 0x34000000) and (w & 31) == reg, (hex(off), hex(w))
        else:
            assert (w & 0xFC000000) == 0x94000000, (hex(off), hex(w))
        struct.pack_into("<I", d, off, NOP)
        print("patched %#x (%s was %#010x)" % (off, kind, w))
p.write_bytes(bytes(d))
print("DisplayDxe NPA patch:", mode)
