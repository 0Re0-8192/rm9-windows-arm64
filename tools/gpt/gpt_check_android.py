"""Read-only GPT health check of all UFS LUNs from a running Android (root via su). usage: gpt_check_android.py"""
import os
import struct
import subprocess
import zlib

ADB = r"C:\ADB\adb.exe"
os.environ.setdefault("ANDROID_SERIAL", "<PHONE_SERIAL>")  # new PC: a second adb device may be attached


def sh(cmd):
    return subprocess.run([ADB, "exec-out", cmd], capture_output=True).stdout


def lun_sizes():
    out = sh("su -c 'cat /proc/partitions'").decode()
    sizes = {}
    for ln in out.splitlines():
        p = ln.split()
        if len(p) == 4 and p[3] in ("sda", "sdb", "sdc", "sdd", "sde", "sdf"):
            sizes[p[3]] = int(p[2]) * 1024
    return sizes


def parse(d, base=0):
    h = d[base:base + 92]
    if h[:8] != b"EFI PART":
        return None
    hs = struct.unpack_from("<I", h, 12)[0]
    crc = struct.unpack_from("<I", h, 16)[0]
    my, alt, fu, lu = struct.unpack_from("<QQQQ", h, 24)
    el = struct.unpack_from("<Q", h, 72)[0]
    num, esz, ecrc = struct.unpack_from("<III", h, 80)
    hh = bytearray(h[:hs]); hh[16:20] = b"\0\0\0\0"
    return dict(my=my, alt=alt, first=fu, last=lu, el=el, num=num, esz=esz, ecrc=ecrc,
                hok=(zlib.crc32(bytes(hh)) & 0xFFFFFFFF) == crc)


print("battery:", sh("dumpsys battery | grep -E 'level|temperature|voltage|status'").decode().replace("\n", " "))
for name, size in sorted(lun_sizes().items()):
    sec = size // 4096
    head = sh("su -c 'dd if=/dev/block/%s bs=4096 count=34 2>/dev/null'" % name)
    pri = parse(head, 4096)
    tail_start = sec - 34
    tail = sh("su -c 'dd if=/dev/block/%s bs=4096 skip=%d count=34 2>/dev/null'" % (name, tail_start))
    bak = parse(tail, (sec - 1 - tail_start) * 4096)
    ok = False
    if pri and bak:
        pe = head[pri["el"] * 4096:pri["el"] * 4096 + pri["num"] * pri["esz"]]
        be = tail[(bak["el"] - tail_start) * 4096:(bak["el"] - tail_start) * 4096 + bak["num"] * bak["esz"]]
        ok = (pri["hok"] and bak["hok"] and pe == be and zlib.crc32(pe) & 0xFFFFFFFF == pri["ecrc"]
              and pri["el"] == 2 and pri["last"] == bak["last"] and pri["alt"] == bak["my"])
    print("%s: sectors=%d primary=%s backup=%s -> %s" % (
        name, sec, ("hdrCRC=%s entriesLBA=%d last=%d" % (pri["hok"], pri["el"], pri["last"])) if pri else "NONE",
        ("hdrCRC=%s last=%d" % (bak["hok"], bak["last"])) if bak else "NONE", "CONSISTENT" if ok else "CHECK"))
