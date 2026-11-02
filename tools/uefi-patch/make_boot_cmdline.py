"""Copy a boot image (header v3/v4) and replace its kernel cmdline field (offset 44, 1536 bytes).
For RAM-only `fastboot boot` experiments (the phone accepts the modified header in orange state).
usage: make_boot_cmdline.py <in.img> <out.img> "<cmdline>"
"""
import sys

src, dst, cmdline = sys.argv[1], sys.argv[2], sys.argv[3]
d = bytearray(open(src, "rb").read())
assert d[:8] == b"ANDROID!", "not a boot image"
ver = int.from_bytes(d[40:44], "little")
assert ver in (3, 4), f"header v{ver} not supported"
c = cmdline.encode()
assert len(c) < 1536, "cmdline too long"
old = bytes(d[44:44 + 1536]).rstrip(b"\0").decode()
d[44:44 + 1536] = c + b"\0" * (1536 - len(c))
open(dst, "wb").write(d)
print(f"v{ver}: cmdline {old!r} -> {cmdline!r}")
