import sys
sys.path.insert(0, "<RM9_WORKDIR>/refs")
from ntfs_remote import NTFS, Remote
n = NTFS(Remote())
vi = n.mft.get(3).attributes[0x70][0]
d = vi.data() if callable(vi.data) else vi.data
d = bytes(d) if not isinstance(d, bytes) else d
print("VOLUME_INFORMATION raw:", d.hex())
if len(d) >= 12:
    f = int.from_bytes(d[10:12], "little")
    print("NTFS %d.%d flags=0x%04X dirty=%s resize_logfile=%s upgrade_on_mount=%s mounted_on_nt4=%s chkdsk_scheduled=%s" % (d[8], d[9], f, bool(f & 1), bool(f & 2), bool(f & 4), bool(f & 8), bool(f & 0x10)))
