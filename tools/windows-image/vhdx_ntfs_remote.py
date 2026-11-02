#!/usr/bin/env python3
"""Read files INSIDE the phone's C:\\w26100.vhdx (dynamic VHDX on the NTFS 'windows' partition), read-only, over adb (run inside WSL, like ntfs_remote.py).
Layers: adb 1 MiB chunks -> outer NTFS (dissect.ntfs) -> the vhdx file stream -> a minimal VHDX reader (BAT) -> inner partition (MBR/GPT, or bare NTFS) -> inner NTFS.

  vhdx_ntfs_remote.py ls  Windows
  vhdx_ntfs_remote.py cat rm9/setupcomplete.txt [out_file]
  vhdx_ntfs_remote.py find Windows/Panther
  vhdx_ntfs_remote.py info
The adb server can be a remote one:  ADB_SERVER_SOCKET=tcp:127.0.0.1:5038 (ssh -L 5038:127.0.0.1:5037 to the second PC); WSLENV is extended here.
"""
import os
import struct
import sys
import uuid

os.environ.setdefault("ADB_SERVER_SOCKET", "tcp:127.0.0.1:5038")
os.environ["WSLENV"] = ":".join(x for x in (os.environ.get("WSLENV", ""), "ADB_SERVER_SOCKET") if x and "ADB_SERVER_SOCKET" not in x.split(":")) + ":ADB_SERVER_SOCKET"
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ntfs_remote as NR
from dissect.ntfs import NTFS

G_BAT = uuid.UUID("2DC27766-F623-4200-9D64-115E9BFD4A08")
G_META = uuid.UUID("8B7CA206-4790-4B9A-B8FE-575F050F886E")
G_FILEPARAM = uuid.UUID("CAA16737-FA36-4D43-B3B6-33F0AA44E76B")
G_DISKSIZE = uuid.UUID("2FA54224-CD1B-4876-B211-5DBED83BF4B8")
G_LSS = uuid.UUID("8141BF1D-A96F-4709-BA47-F233A8FAAB5F")


class Vhdx:
    def __init__(self, fh):
        self.f = fh
        fh.seek(0)
        if fh.read(8) != b"vhdxfile":
            raise ValueError("not a vhdx")
        # region table (the first copy at 192 KiB)
        fh.seek(192 * 1024)
        rt = fh.read(65536)
        if rt[:4] != b"regi":
            raise ValueError("no region table")
        cnt = struct.unpack_from("<I", rt, 8)[0]
        reg = {}
        for i in range(cnt):
            g, off, ln, req = struct.unpack_from("<16sQII", rt, 16 + 32 * i)
            reg[uuid.UUID(bytes_le=g)] = (off, ln)
        bat_off, bat_len = reg[G_BAT]
        meta_off, meta_len = reg[G_META]
        fh.seek(meta_off)
        md = fh.read(meta_len)
        n = struct.unpack_from("<H", md, 10)[0]
        items = {}
        for i in range(n):
            g, o, ln, fl = struct.unpack_from("<16sIII", md, 32 + 32 * i)
            items[uuid.UUID(bytes_le=g)] = (o, ln)
        o, _ = items[G_FILEPARAM]
        self.block = struct.unpack_from("<I", md, o)[0]
        self.size = struct.unpack_from("<Q", md, items[G_DISKSIZE][0])[0]
        self.lss = struct.unpack_from("<I", md, items[G_LSS][0])[0]
        self.ratio = (1 << 23) * self.lss // self.block
        fh.seek(bat_off)
        self.bat = fh.read(bat_len)
        self.pos = 0
        self.cache = {}

    def _block(self, i):
        if i in self.cache:
            return self.cache[i]
        bi = i + i // self.ratio
        ent = struct.unpack_from("<Q", self.bat, 8 * bi)[0]
        state = ent & 7
        if state == 6:
            self.f.seek((ent >> 20) << 20)
            d = self.f.read(self.block)
        else:
            d = bytes(self.block)
        if len(self.cache) > 8:
            self.cache.pop(next(iter(self.cache)))
        self.cache[i] = d
        return d

    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else self.size + off)
        return self.pos

    def tell(self):
        return self.pos

    def read(self, n=-1):
        if n < 0:
            n = self.size - self.pos
        n = min(n, self.size - self.pos)
        out = bytearray()
        while n > 0:
            i, o = divmod(self.pos, self.block)
            d = self._block(i)
            take = min(n, self.block - o)
            out += d[o:o + take]
            self.pos += take
            n -= take
        return bytes(out)


class Window:
    def __init__(self, fh, off, size):
        self.f, self.off, self.size, self.pos = fh, off, size, 0

    def seek(self, o, whence=0):
        self.pos = o if whence == 0 else (self.pos + o if whence == 1 else self.size + o)
        return self.pos

    def tell(self):
        return self.pos

    def read(self, n=-1):
        if n < 0:
            n = self.size - self.pos
        n = min(n, self.size - self.pos)
        self.f.seek(self.off + self.pos)
        d = self.f.read(n)
        self.pos += len(d)
        return d


def find_ntfs(v):
    """offset/size of the inner NTFS: try MBR partitions, GPT partitions, then 1 MiB"""
    v.seek(0)
    s0 = v.read(512)
    cands = []
    if s0[510:512] == b"\x55\xaa":
        for i in range(4):
            e = s0[446 + 16 * i:462 + 16 * i]
            start, cnt = struct.unpack_from("<II", e, 8)
            if cnt and e[4] != 0xEE:
                cands.append((start * 512, cnt * 512))
    v.seek(512)
    h = v.read(512)
    if h[:8] == b"EFI PART":
        lba, n, sz = struct.unpack_from("<QII", h, 72)
        v.seek(lba * 512)
        t = v.read(n * sz)
        for i in range(n):
            e = t[i * sz:(i + 1) * sz]
            if e[:16] != bytes(16):
                a, b = struct.unpack_from("<QQ", e, 32)
                cands.append((a * 512, (b - a + 1) * 512))
    cands.append((1 << 20, v.size - (1 << 20)))
    for off, size in cands:
        v.seek(off + 3)
        if v.read(8) == b"NTFS    ":
            return off, size
    raise ValueError("no NTFS inside the vhdx")


def open_inner(vhdx_path="w26100.vhdx"):
    outer = NTFS(NR.Remote())
    rec = outer.mft.get(vhdx_path)
    v = Vhdx(rec.open())
    off, size = find_ntfs(v)
    return NTFS(Window(v, off, size)), v, off


def main():
    cmd = sys.argv[1]
    path = sys.argv[2] if len(sys.argv) > 2 else ""
    ntfs, v, off = open_inner()
    if cmd == "info":
        print("vhdx size", v.size, "block", v.block, "lss", v.lss, "inner NTFS at", off)
        return
    if cmd in ("ls", "find"):
        rec = ntfs.mft.get(path) if path else ntfs.mft.root
        for name in sorted(rec.listdir().keys()):
            print(name)
        return
    if cmd == "cat":
        rec = ntfs.mft.get(path)
        d = rec.open().read()
        if len(sys.argv) > 3:
            open(sys.argv[3], "wb").write(d)
            print(len(d), "bytes ->", sys.argv[3], file=sys.stderr)
        else:
            sys.stdout.buffer.write(d)
        return
    if cmd == "get":       # get <outdir> <path>...   (one session, many files; a directory path = all its files)
        outdir = sys.argv[2]
        os.makedirs(outdir, exist_ok=True)
        for p in sys.argv[3:]:
            try:
                rec = ntfs.mft.get(p)
                names = [(p, rec)] if not rec.is_dir() else [(p + "/" + n, ntfs.mft.get(p + "/" + n)) for n in sorted(rec.listdir().keys())]
                for q, r in names:
                    if r.is_dir():
                        print("dir", q)
                        continue
                    d = r.open().read()
                    open(os.path.join(outdir, q.replace("/", "_")), "wb").write(d)
                    print("got", q, len(d))
            except Exception as e:
                print("fail", p, repr(e))
        return
    print("usage: ls|cat|get|info", file=sys.stderr)


main()
