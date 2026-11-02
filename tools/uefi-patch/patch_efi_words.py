"""Write 32-bit words into a prebuilt Mu binary (always from <file>.rm9orig2).  usage (WSL): python3 patch_efi_words.py <efi> <hex off>=<hex word> ...  (no pairs = restore)"""
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
    off, w = (int(x, 16) for x in a.split("="))
    old = struct.unpack_from("<I", d, off)[0]
    struct.pack_into("<I", d, off, w)
    print("%#x: %#010x -> %#010x" % (off, old, w))
p.write_bytes(bytes(d))
