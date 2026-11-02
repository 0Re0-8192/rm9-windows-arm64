#!/usr/bin/env python3
"""List files on the phone's NTFS partition modified after a given date (read-only, over adb).
  python3 ntfs_recent.py 2026-10-13 [dir ...]"""
import datetime
import sys

sys.path.insert(0, "<RM9_WORKDIR>/refs")
from ntfs_remote import NTFS, Remote  # noqa: E402

since = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%d")
dirs = sys.argv[2:] or ["", "Windows", "Windows/System32/config", "Windows/Logs", "Windows/System32/LogFiles",
                        "Windows/Panther", "Windows/System32/winevt/Logs", "Windows/ServiceProfiles", "ProgramData",
                        "Users", "System Volume Information", "$Recycle.Bin", "Recovery"]
fh = Remote()
ntfs = NTFS(fh)
found = 0


def mtime(rec):
    try:
        si = rec.attributes[16][0]
        t = si.last_modification_time
        return t.replace(tzinfo=None) if hasattr(t, "replace") else t
    except Exception:
        return None


for d in dirs:
    try:
        rec = ntfs.mft.get(d) if d else ntfs.mft.root
        names = list(rec.listdir().items())
    except Exception as e:
        print("[skip %s: %s]" % (d, e))
        continue
    for name, ent in names:
        try:
            child = ent.dereference()
            t = mtime(child)
        except Exception:
            continue
        if t and t >= since:
            print("%s  %s/%s" % (t.strftime("%Y-%m-%d %H:%M:%S"), d, name))
            found += 1
print("[%d recent entries; fetched %d MiB]" % (found, fh.fetches))
