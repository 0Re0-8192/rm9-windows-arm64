#!/usr/bin/env python3
"""READ-ONLY on the phone: copy the ALLOCATED 1 MiB chunks of the 'windows' partition (per the NTFS $Bitmap) into a sparse image.
Run inside WSL while Android is up (root via su; the partition is not mounted).  The result is a faithful image of the phone's NTFS
(holes = unallocated space).  usage: pull_windows_used.py /root/win_phone.img"""
import os
import subprocess
import sys
import time

sys.path.insert(0, "<RM9_WORKDIR>/refs")
from ntfs_remote import NTFS, Remote, SIZE  # noqa: E402

ADB = "/mnt/c/ADB/adb.exe"
CH = 1 << 20
out = sys.argv[1]

fh = Remote()
n = NTFS(fh)
bm = n.mft.get("$Bitmap")
data = bm.open().read()
print("bitmap bytes", len(data), "clusters covered", len(data) * 8, "cluster size", n.cluster_size, flush=True)
per_chunk_bytes = (CH // n.cluster_size) // 8          # bitmap bytes per 1 MiB chunk
nchunks = (SIZE + CH - 1) // CH
used = [c for c in range(nchunks) if any(data[c * per_chunk_bytes:(c + 1) * per_chunk_bytes])]
print("chunks total", nchunks, "allocated", len(used), "(%.1f GiB)" % (len(used) / 1024), flush=True)
# metadata that lives outside what the bitmap shows as allocated: the boot sector area and the backup boot sector (last sector)
for c in (0, nchunks - 1):
    if c not in used:
        used.append(c)
used.sort()

with open(out, "wb") as f:
    f.truncate(SIZE)
    t0 = time.time()
    done = 0
    i = 0
    while i < len(used):
        j = i
        while j + 1 < len(used) and used[j + 1] == used[j] + 1 and j - i < 63:
            j += 1
        s, cnt = used[i], j - i + 1
        for attempt in range(4):
            d = subprocess.run([ADB, "exec-out", "su -c 'dd if=/dev/block/by-name/windows bs=1048576 skip=%d count=%d 2>/dev/null'" % (s, cnt)],
                               capture_output=True).stdout
            expect = min(cnt * CH, SIZE - s * CH)
            if len(d) == expect:
                break
            print("short read at chunk", s, len(d), "!=", expect, "retry", attempt, flush=True)
            time.sleep(2)
        else:
            sys.exit("giving up at chunk %d" % s)
        if any(d):
            f.seek(s * CH)
            f.write(d)
        done += cnt
        i = j + 1
        if (i // 64) % 10 == 0:
            print("%d/%d chunks  %.0f s  %.1f MiB/s" % (done, len(used), time.time() - t0, done / max(time.time() - t0, 1e-6)), flush=True)
print("DONE", done, "chunks in", round(time.time() - t0), "s ->", out)
