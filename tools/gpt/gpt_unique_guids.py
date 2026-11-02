"""A': make partition unique-GUIDs distinct across LUNs on the live device (LUN0 = sda, LUN5 = sdf), touching ONLY entries whose
GUID currently collides with another LUN's.  Entries Windows depends on (esp/msr/windows, i.e. unique GUIDs already) are kept.

  gpt_unique_guids.py plan    read-only: read sda/sdf GPT via adb+su, write backups + new sectors into winboot/aprime/, print diff
  gpt_unique_guids.py apply   write the planned sectors (backup GPT first, then primary entries, then primary header), flush, verify
"""
import hashlib
import struct
import subprocess
import sys
import uuid
import zlib
from pathlib import Path

ADB = r"C:\ADB\adb.exe"
OUT = Path(r"<RM9_WORKDIR>\winboot\aprime")
S = 4096
# Which LUNs to rewrite (device node -> LUN number).  Other LUNs are only READ to find collisions.
TARGET = {"sda": 0, "sdf": 5}
ALL = {"sda": 0, "sdb": 1, "sdc": 2, "sdd": 3, "sde": 4, "sdf": 5}


def sh(cmd):
    r = subprocess.run([ADB, "exec-out", cmd], capture_output=True)
    return r.stdout


def read_sectors(dev, lba, count):
    d = sh("su -c 'dd if=/dev/block/%s bs=%d skip=%d count=%d 2>/dev/null'" % (dev, S, lba, count))
    assert len(d) == S * count, (dev, lba, count, len(d))
    return d


def parse_hdr(h):
    assert h[:8] == b"EFI PART"
    my, alt, fu, lu = struct.unpack_from("<QQQQ", h, 24)
    el, n, sz = struct.unpack_from("<QII", h, 72)
    return dict(my=my, alt=alt, first=fu, last=lu, ent=el, n=n, sz=sz)


def crc_hdr(h):
    b = bytearray(h[:92])
    b[16:20] = b"\0\0\0\0"
    return zlib.crc32(bytes(b)) & 0xFFFFFFFF


def load(dev):
    """returns dict with primary header/entries and backup header/entries (raw bytes), all verified"""
    p = read_sectors(dev, 1, 1)
    ph = parse_hdr(p)
    assert crc_hdr(p) == struct.unpack_from("<I", p, 16)[0], "primary hdr CRC"
    ent_sectors = (ph["n"] * ph["sz"] + S - 1) // S
    pe = read_sectors(dev, ph["ent"], ent_sectors)[: ph["n"] * ph["sz"]]
    assert zlib.crc32(pe) & 0xFFFFFFFF == struct.unpack_from("<I", p, 88)[0], "primary entries CRC"
    b = read_sectors(dev, ph["alt"], 1)
    bh = parse_hdr(b)
    assert crc_hdr(b) == struct.unpack_from("<I", b, 16)[0], "backup hdr CRC"
    be = read_sectors(dev, bh["ent"], ent_sectors)[: bh["n"] * bh["sz"]]
    assert zlib.crc32(be) & 0xFFFFFFFF == struct.unpack_from("<I", b, 88)[0], "backup entries CRC"
    assert pe == be, "primary/backup entries differ"
    return dict(dev=dev, p=bytes(p[:92]), ph=ph, pe=pe, b=bytes(b[:92]), bh=bh, ent_sectors=ent_sectors)


def entries(e, sz=128):
    for i in range(len(e) // sz):
        x = e[i * sz:(i + 1) * sz]
        if x[:16] != b"\0" * 16:
            yield i, uuid.UUID(bytes_le=x[16:32]), x[56:128].decode("utf-16le").rstrip("\0")


def plan():
    OUT.mkdir(parents=True, exist_ok=True)
    gpts = {d: load(d) for d in ALL}
    count = {}
    for d, g in gpts.items():
        for i, guid, name in entries(g["pe"]):
            count.setdefault(guid, []).append((ALL[d], i, name))
    dups = {g for g, v in count.items() if len(v) > 1}
    print("partitions:", sum(len(v) for v in count.values()), " colliding GUIDs:", len(dups))
    manifest = []
    for d in TARGET:
        g = gpts[d]
        pe = bytearray(g["pe"])
        changed = []
        for i, guid, name in entries(g["pe"]):
            if guid in dups:
                new = uuid.uuid4()
                pe[i * g["ph"]["sz"] + 16:i * g["ph"]["sz"] + 32] = new.bytes_le
                changed.append((i, name, guid, new))
        # keep the same CRC logic as the original: entry array CRC covers n*sz bytes
        ecrc = zlib.crc32(bytes(pe)) & 0xFFFFFFFF
        ph = bytearray(g["p"]); bh = bytearray(g["b"])
        for h in (ph, bh):
            struct.pack_into("<I", h, 88, ecrc)
            h[16:20] = b"\0\0\0\0"
            struct.pack_into("<I", h, 16, crc_hdr(bytes(h)))
        # raw sectors to write (4096 B each)
        pad = lambda x: bytes(x) + b"\0" * (S * ((len(x) + S - 1) // S) - len(x))
        files = {
            "%s_primary_hdr.bin" % d: (g["ph"]["my"], bytes(ph) + b"\0" * (S - 92)),
            "%s_primary_ent.bin" % d: (g["ph"]["ent"], pad(pe)),
            "%s_backup_ent.bin" % d: (g["bh"]["ent"], pad(pe)),
            "%s_backup_hdr.bin" % d: (g["bh"]["my"], bytes(bh) + b"\0" * (S - 92)),
        }
        # originals (for rollback)
        orig = {
            "%s_primary_hdr.bin.orig" % d: g["p"] + b"\0" * (S - 92),
            "%s_primary_ent.bin.orig" % d: pad(g["pe"]),
            "%s_backup_ent.bin.orig" % d: pad(g["pe"]),
            "%s_backup_hdr.bin.orig" % d: g["b"] + b"\0" * (S - 92),
        }
        for k, (lba, data) in files.items():
            (OUT / k).write_bytes(data)
            manifest.append("%s lba=%d sectors=%d" % (k, lba, len(data) // S))
        for k, data in orig.items():
            (OUT / k).write_bytes(data)
        print("== %s (LUN%d): %d entries change" % (d, TARGET[d], len(changed)))
        for i, name, o, n in changed:
            print("   #%-3d %-22s %s -> %s" % (i, name, o, n))
        keep = [(i, name, guid) for i, guid, name in entries(g["pe"]) if guid not in dups]
        print("   unchanged (unique already):", ", ".join(name for _, name, _ in keep))
    (OUT / "manifest.txt").write_text("\n".join(manifest) + "\n")
    print("plan written to", OUT)


def apply():
    man = (OUT / "manifest.txt").read_text().split("\n")
    order = ["backup_ent", "backup_hdr", "primary_ent", "primary_hdr"]   # backup first, primary header LAST
    for d in TARGET:
        # re-validate that the disk still holds exactly the planned originals
        g = load(d)
        assert (OUT / ("%s_primary_hdr.bin.orig" % d)).read_bytes()[:92] == g["p"], "disk changed since plan"
        for part in order:
            name = "%s_%s.bin" % (d, part)
            lba = [int(l.split("lba=")[1].split()[0]) for l in man if l.startswith(name)][0]
            data = (OUT / name).read_bytes()
            sub = subprocess.run([ADB, "push", str(OUT / name), "/data/local/tmp/" + name], capture_output=True)
            assert sub.returncode == 0, sub.stderr
            out = sh("su -c 'dd if=/data/local/tmp/%s of=/dev/block/%s bs=%d seek=%d conv=notrunc,fsync 2>&1; sync; rm /data/local/tmp/%s'" % (name, d, S, lba, name))
            print(d, part, "lba", lba, "sectors", len(data) // S, out.decode(errors="replace").strip().splitlines()[-1:])
        sh("su -c 'blockdev --flushbufs /dev/block/%s'" % d)
    print("applied; verify with gpt_check_android.py and a reboot")


if __name__ == "__main__":
    {"plan": plan, "apply": apply}[sys.argv[1]]()
