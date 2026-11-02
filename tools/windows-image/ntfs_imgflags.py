import sys
from dissect.ntfs import NTFS
for p in ("/root/win_v3.img", "/root/win_v4.img"):
    with open(p, "rb") as f:
        n = NTFS(f)
        d = bytes(n.mft.get(3).attributes[0x70][0].data())
        fl = int.from_bytes(d[10:12], "little")
        print(p, "flags=0x%04X dirty=%s" % (fl, bool(fl & 1)))
