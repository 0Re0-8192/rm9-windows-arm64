#!/usr/bin/env python3
"""Read-only: NTFS volume state of the phone's windows partition ($Volume flags incl. dirty bit, boot sector, $LogFile header, a few MFT stamps).
run in WSL:  /root/.venv/bin/python3 ntfs_volinfo.py"""
import sys

sys.path.insert(0, "<RM9_WORKDIR>/refs")
from ntfs_remote import NTFS, Remote  # noqa: E402

fh = Remote()
n = NTFS(fh)
print("sector size", n.sector_size, "cluster size", n.cluster_size, "mft record size", n.mft.record_size if hasattr(n.mft, "record_size") else "?")
vol = n.mft.get(3)                                  # $Volume
for a in vol.attributes.get(0x70, []) or []:       # VOLUME_INFORMATION
    d = a.dump() if hasattr(a, "dump") else None
    print("VOLUME_INFORMATION:", d if d is not None else a)
try:
    vi = vol.attributes[0x70][0]
    raw = vi.dump() if hasattr(vi, "dump") else bytes(vi.value) if hasattr(vi, "value") else b""
    print("raw:", raw.hex())
    if raw and len(raw) >= 12:
        flags = int.from_bytes(raw[10:12], "little")
        print("flags 0x%04X: dirty=%s resize_logfile=%s upgrade_on_mount=%s mounted_on_nt4=%s chkdsk_initiated=%s" % (
            flags, bool(flags & 1), bool(flags & 2), bool(flags & 4), bool(flags & 8), bool(flags & 0x10)))
except Exception as e:
    print("flags parse failed:", e)
print("fetches", fh.fetches)
