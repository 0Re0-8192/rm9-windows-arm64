"""Put a BRK at given RVAs of the (already NPA-patched) DisplayDxe.efi to bisect a hang: the CPU exception dump names the first BRK reached.
usage (WSL): python3 patch_displaydxe_brk.py <hex rva> [<hex rva> ...]      (no args = remove all BRKs: re-apply patch_displaydxe_npa.py on)"""
import struct
import sys
from pathlib import Path

p = Path("/root/Mu-Silicium/Binaries/nx769j/QcomPkg/Drivers/DisplayDxe/DisplayDxe.efi")
d = bytearray(p.read_bytes())
for a in sys.argv[1:]:
    off = int(a, 16)
    old = struct.unpack_from("<I", d, off)[0]
    struct.pack_into("<I", d, off, 0xD4200020)      # brk #1
    print("brk at %#x (was %#010x)" % (off, old))
p.write_bytes(bytes(d))
