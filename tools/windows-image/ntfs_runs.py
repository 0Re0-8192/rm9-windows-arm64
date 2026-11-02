#!/usr/bin/env python3
"""Print the on-disk extents (byte offset, length) of files on the phone's NTFS 'windows' partition (run in WSL, see ntfs_remote.py).
  ntfs_runs.py Windows/System32/drivers/rm9hid.sys ...
Output per file: size, then "offset length" in bytes relative to the partition start (non-resident data only)."""
import sys
sys.path.insert(0, "<RM9_WORKDIR>/refs")
from ntfs_remote import Remote, NTFS

fh = Remote()
ntfs = NTFS(fh)
cs = ntfs.cluster_size
for p in sys.argv[1:]:
    rec = ntfs.mft.get(p)
    st = rec.open()
    print(p, "size", st.size)
    off = 0
    for lcn, cnt in st.runlist:
        if lcn is None:
            print("  sparse", cnt * cs)
        else:
            print("  extent", lcn * cs, cnt * cs)
