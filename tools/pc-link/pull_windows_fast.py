#!/usr/bin/env python3
"""Parallel version of pull_windows_used.py: READ-ONLY on the phone; copy the ALLOCATED 1 MiB chunks of the 'windows' partition (per the NTFS $Bitmap)
into a sparse image using several concurrent adb streams.  Run inside WSL while Android is up.   usage: pull_windows_fast.py /root/win_phone.img [workers]"""
import os
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, "<RM9_WORKDIR>/refs")
from ntfs_remote import NTFS, Remote, SIZE  # noqa: E402

ADB = "/mnt/c/ADB/adb.exe"
CH = 1 << 20
out = sys.argv[1]
workers = int(sys.argv[2]) if len(sys.argv) > 2 else 8

n = NTFS(Remote())
data = n.mft.get("$Bitmap").open().read()
per = (CH // n.cluster_size) // 8
nchunks = (SIZE + CH - 1) // CH
used = [c for c in range(nchunks) if any(data[c * per:(c + 1) * per])]
for c in (0, nchunks - 1):
    if c not in used:
        used.append(c)
used.sort()
print("chunks total", nchunks, "allocated", len(used), "(%.1f GiB)" % (len(used) / 1024), flush=True)

groups = []
i = 0
while i < len(used):
    j = i
    while j + 1 < len(used) and used[j + 1] == used[j] + 1 and j - i < 31:
        j += 1
    groups.append((used[i], j - i + 1))
    i = j + 1

fd = os.open(out, os.O_RDWR | os.O_CREAT, 0o644)
os.ftruncate(fd, SIZE)
lock = threading.Lock()
done = [0]
t0 = time.time()


def work(g):
    s, cnt = g
    expect = min(cnt * CH, SIZE - s * CH)
    for attempt in range(5):
        d = subprocess.run([ADB, "exec-out", "su -c 'dd if=/dev/block/by-name/windows bs=1048576 skip=%d count=%d 2>/dev/null'" % (s, cnt)],
                           capture_output=True).stdout
        if len(d) == expect:
            break
        time.sleep(2)
    else:
        raise RuntimeError("giving up at chunk %d" % s)
    if any(d):
        os.pwrite(fd, d, s * CH)
    with lock:
        done[0] += cnt
        if (done[0] // 32) % 20 == 0:
            print("%d/%d chunks %.0f s %.1f MiB/s" % (done[0], len(used), time.time() - t0, done[0] / max(time.time() - t0, 1e-6)), flush=True)


with ThreadPoolExecutor(workers) as ex:
    list(ex.map(work, groups))
os.close(fd)
print("DONE", done[0], "chunks in", round(time.time() - t0), "s ->", out, flush=True)
