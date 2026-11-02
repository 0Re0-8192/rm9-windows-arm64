"""Put halting `brk #1` at RVAs of a prebuilt Mu binary driver (keeps <file>.rm9orig, always patches from it).
usage (WSL): python3 patch_efi_brk.py <efi path> [<hex rva> ...]     (no rva = restore the original)"""
import shutil
import struct
import sys
from pathlib import Path

p = Path(sys.argv[1])
o = p.with_suffix(".efi.rm9orig2")
if not o.exists():
    shutil.copy(p, o)
d = bytearray(o.read_bytes())
for a in sys.argv[2:]:
    off = int(a, 16)
    old = struct.unpack_from("<I", d, off)[0]
    struct.pack_into("<I", d, off, 0xD4200020)
    print("brk at %#x (was %#010x)" % (off, old))
p.write_bytes(bytes(d))
