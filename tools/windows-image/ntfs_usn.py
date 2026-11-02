#!/usr/bin/env python3
"""List files changed on the phone's NTFS 'windows' partition since a UTC timestamp, from the USN journal (run in WSL).
  ntfs_usn.py "2026-10-19 05:21:00"   -> unique (file name, reasons) lines, plus the parent directory when known"""
import sys
from collections import OrderedDict
from datetime import datetime, timezone
sys.path.insert(0, "<RM9_WORKDIR>/refs")
from ntfs_remote import Remote, NTFS

since = datetime.strptime(sys.argv[1], "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
ntfs = NTFS(Remote())
seen = OrderedDict()
n = 0
for rec in ntfs.usnjrnl.records():
    n += 1
    ts = rec.timestamp
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=timezone.utc)
    if ts < since:
        continue
    key = (str(rec.full_path) if hasattr(rec, "full_path") else str(rec.filename))
    seen.setdefault(key, set()).add(str(rec.Reason))
print("records scanned", n, "changed files", len(seen))
for k, v in seen.items():
    print(k, "|", ",".join(sorted(v))[:80])

