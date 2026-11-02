"""Turn the `bl` instructions of the given RVA ranges of the (already NPA-patched) DisplayDxe.efi into non-halting trace points
(see patch_exc_trace.py).  Calls to the usual helper functions are left alone.  Targets within +-64 KiB are encoded in the brk immediate, farther ones through
the handler's mRm9Far[] table (rewritten here).  Run after patch_exc_trace.py on and patch_displaydxe_npa.py on.
usage (WSL): python3 patch_displaydxe_trace.py <lo>-<hi> [<lo>-<hi> ...]   (hex RVAs)"""
import struct
import sys
from pathlib import Path

p = Path("/root/Mu-Silicium/Binaries/nx769j/QcomPkg/Drivers/DisplayDxe/DisplayDxe.efi")
h = Path("/root/Mu-Silicium/Mu_Basecore/UefiCpuPkg/Library/CpuExceptionHandlerLib/AArch64/CpuExceptionHandlerLib.c")
d = bytearray(p.read_bytes())
SKIP = {0x1A50C, 0x1A268, 0x131D8, 0x21A40, 0x1A0E8, 0x10D0, 0x1CE44, 0x23944, 0x1A2D4, 0x11548, 0x11684, 0x1167C, 0x116D0, 0x116D8, 0x4180,
        0x21B40, 0x1A53C, 0x1A540, 0x239CC, 0x113E0}
far = []
n = 0
for rng in sys.argv[1:]:
    lo, hi = (int(x, 16) for x in rng.split("-"))
    for off in range(lo, hi, 4):
        w = struct.unpack_from("<I", d, off)[0]
        if (w & 0xFC000000) != 0x94000000:
            continue
        imm = w & 0x3FFFFFF
        if imm & 0x2000000:
            imm -= 0x4000000
        tgt = off + imm * 4
        if tgt in SKIP:
            continue
        if -0x4000 <= imm < 0x4000 and imm != 1:
            struct.pack_into("<I", d, off, 0xD4200000 | ((imm & 0xFFFF) << 5))        # brk #disp16 (signed words)
        else:
            far.append(imm)
            assert len(far) <= 0x4000
            struct.pack_into("<I", d, off, 0xD4200000 | ((0x8000 + len(far) - 1) << 5))
        n += 1
p.write_bytes(bytes(d))
t = h.read_text(encoding="utf-8")
a = t.index("/* RM9FAR */") + len("/* RM9FAR */")
b = t.index("/* END RM9FAR */")
t = t[:a] + " " + (", ".join(str(x) for x in far) if far else "0") + " " + t[b:]
h.write_text(t, encoding="utf-8")
print("trace points:", n, "far:", len(far))

