#!/usr/bin/env python3
"""Flash only the 1 MiB chunks that differ between a Windows partition stored INSIDE a disk image (NEW, at a byte offset) and the BASE partition image
(= exactly what the phone's partition contained when BASE was pulled).  Each written chunk is read back and verified.  Device must be in recovery (TWRP).
  python3 flash_patch.py /root/qemu/disk.img 603979776 /root/win_phone.img
"""
import os
import subprocess
import sys
import time

ADB = "/mnt/c/ADB/adb.exe"
CH = 1 << 20
PART = "windows"
new_path, off, base_path = sys.argv[1], int(sys.argv[2]), sys.argv[3]
SIZE = os.path.getsize(base_path)          # partition size (the base image is exactly partition-sized)
if subprocess.run([ADB, "get-state"], capture_output=True).stdout.decode().strip() != "recovery":
    sys.exit("device not in recovery")


def data_chunks(path, base_off, size):
    fd = os.open(path, os.O_RDONLY)
    s = set()
    pos = base_off
    end = base_off + size
    fsize = os.fstat(fd).st_size
    while pos < min(end, fsize):
        try:
            ds = os.lseek(fd, pos, os.SEEK_DATA)
        except OSError:
            break
        if ds >= end:
            break
        de = min(os.lseek(fd, ds, os.SEEK_HOLE), end)
        for c in range((ds - base_off) // CH, (de - base_off + CH - 1) // CH):
            s.add(c)
        pos = de
    os.close(fd)
    return s


nc = data_chunks(new_path, off, SIZE)
bc = data_chunks(base_path, 0, SIZE)
fn, fb = open(new_path, "rb"), open(base_path, "rb")


def rd(f, base_off, c):
    f.seek(base_off + c * CH)
    d = f.read(min(CH, SIZE - c * CH))
    return d + bytes(min(CH, SIZE - c * CH) - len(d))


changed = [c for c in sorted(nc | bc) if rd(fn, off, c) != rd(fb, 0, c)]
print("changed 1MiB chunks:", len(changed), flush=True)
t0 = time.time()
bad = 0
i = 0
while i < len(changed):
    j = i
    while j + 1 < len(changed) and changed[j + 1] == changed[j] + 1 and j - i < 63:
        j += 1
    s, n = changed[i], j - i + 1
    buf = b"".join(rd(fn, off, c) for c in range(s, s + n))
    r = subprocess.run([ADB, "exec-in", "busybox dd of=/dev/block/by-name/%s bs=1048576 seek=%d iflag=fullblock conv=notrunc 2>/dev/null" % (PART, s)],
                       input=buf, capture_output=True)
    back = subprocess.run([ADB, "exec-out", "dd if=/dev/block/by-name/%s bs=1048576 skip=%d count=%d 2>/dev/null" % (PART, s, n)], capture_output=True).stdout
    if r.returncode != 0 or back[:len(buf)] != buf:
        bad += 1
        print("VERIFY FAIL @ chunk", s, "n", n, flush=True)
    i = j + 1
    if (i // 64) % 5 == 0:
        print("%d/%d  %.0f s  bad %d" % (i, len(changed), time.time() - t0, bad), flush=True)
print("DONE changed=%d bad=%d" % (len(changed), bad))
sys.exit(1 if bad else 0)
