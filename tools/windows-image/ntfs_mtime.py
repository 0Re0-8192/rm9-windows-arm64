#!/usr/bin/env python3
"""Print modification times of files on the phone's NTFS 'windows' partition (run in WSL).  ntfs_mtime.py path ..."""
import sys
sys.path.insert(0, "<RM9_WORKDIR>/refs")
from ntfs_remote import Remote, NTFS

fh = Remote()
ntfs = NTFS(fh)
for p in sys.argv[1:]:
    try:
        rec = ntfs.mft.get(p)
        si = rec.attributes.STANDARD_INFORMATION[0] if hasattr(rec.attributes,'STANDARD_INFORMATION') else rec.attributes['STANDARD_INFORMATION'][0]
        print(si.last_modification_time, si.last_access_time, "", p)
    except Exception as e:
        print("ERR", p, e)
