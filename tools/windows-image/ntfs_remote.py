#!/usr/bin/env python3
"""Read files from the phone's NTFS 'windows' partition WITHOUT mounting or dumping 128 GB:
a file-like object fetches 1 MiB chunks on demand over adb (TWRP root, or Android su) and
dissect.ntfs parses them.   (run inside WSL; uses the Windows adb.exe via interop)

  ntfs_remote.py ls  Windows
  ntfs_remote.py cat Windows/ntbtlog.txt  [out_file]
  ntfs_remote.py find Windows/Minidump
"""
import os
import subprocess
import sys
from collections import OrderedDict

from dissect.ntfs import NTFS

ADB = "/mnt/c/ADB/adb.exe"
# new PC: a second adb device may be attached -> pin the target; WSLENV forwards the variable to the Windows adb.exe
os.environ.setdefault("ANDROID_SERIAL", "<PHONE_SERIAL>")
if "ANDROID_SERIAL" not in os.environ.get("WSLENV", ""):
    os.environ["WSLENV"] = ":".join(x for x in (os.environ.get("WSLENV", ""), "ANDROID_SERIAL") if x)
DEV = "/dev/block/by-name/windows"
CH = 1 << 20
SIZE = 33442999 * 4096


def _prefix():
    out = subprocess.run([ADB, "shell", "id"], capture_output=True).stdout.decode()
    return "" if "uid=0" in out else "su -c "


class Remote:
    def __init__(self):
        self.pos = 0
        self.cache = OrderedDict()
        self.pre = _prefix()
        self.fetches = 0

    def _chunk(self, n):
        if n in self.cache:
            self.cache.move_to_end(n)
            return self.cache[n]
        cmd = "dd if=%s bs=1048576 skip=%d count=1 2>/dev/null" % (DEV, n)
        if self.pre:
            cmd = "su -c '%s'" % cmd
        d = subprocess.run([ADB, "exec-out", cmd], capture_output=True).stdout
        if len(d) < CH:
            d = d + bytes(CH - len(d))
        self.fetches += 1
        self.cache[n] = d
        if len(self.cache) > 96:
            self.cache.popitem(last=False)
        return d

    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else SIZE + off)
        return self.pos

    def tell(self):
        return self.pos

    def read(self, n=-1):
        if n < 0:
            n = SIZE - self.pos
        n = min(n, SIZE - self.pos)
        out = bytearray()
        while n > 0:
            c, o = divmod(self.pos, CH)
            d = self._chunk(c)
            take = min(n, CH - o)
            out += d[o:o + take]
            self.pos += take
            n -= take
        return bytes(out)


def main():
    cmd = sys.argv[1]
    path = sys.argv[2] if len(sys.argv) > 2 else ""
    fh = Remote()
    ntfs = NTFS(fh)
    if cmd in ("ls", "find"):
        rec = ntfs.mft.get(path) if path else ntfs.mft.root
        for name in sorted(rec.listdir().keys()):
            print(name)
    elif cmd == "cat":
        rec = ntfs.mft.get(path)
        data = rec.open().read()
        if len(sys.argv) > 3:
            open(sys.argv[3], "wb").write(data)
            print("wrote", sys.argv[3], len(data))
        else:
            sys.stdout.buffer.write(data)
    print("[fetched %d MiB]" % fh.fetches, file=sys.stderr)


if __name__ == "__main__":
    main()
