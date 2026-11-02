#!/usr/bin/env python3
"""For Windows runs: seconds between ExitBootServices (cntvct saved by MuChain at 0xD7FF0410) and the last ACPI Timer() stamp seen in the
UFSS snapshots / DBGL ring.  usage: run_timeline.py RAMCON.BIN [RAMCON.BIN ...]"""
import struct
import sys

for p in sys.argv[1:]:
    d = open(p, "rb").read()
    O = 0x1F0000
    u32 = lambda off: struct.unpack_from("<I", d, O + off)[0]
    u64 = lambda off: struct.unpack_from("<Q", d, O + off)[0]
    ebok = u32(0x408) == 0x4B4F4245
    cnt = u64(0x410)
    hb = u32(0x440)
    t_ebs = (cnt / 19.2e6) if ebok else None            # seconds since counter start
    ring_cnt = u32(0)
    times = []
    for k in range(32):
        v = u32(4 + 4 * k)
        if v:
            times.append(v >> 8)                         # 24-bit of Timer() (100 ns units): wraps every 1.67 s -> use only as ordering hint
    stored = struct.unpack_from("<I", d, 0x1F2004)[0]
    last = None
    for k in range(max(0, stored - 16), stored):
        slot = k & 15
        last = struct.unpack_from("<I", d, 0x1F2000 + 0x10 + slot * 48 * 4)[0]
    first = None
    if stored:
        first = struct.unpack_from("<I", d, 0x1F2000 + 0x10 + (max(0, stored - 16) & 15) * 48 * 4)[0]
    print("%s\n  EBOK=%s  EBS counter=%.2f s  heartbeat=%d s  ACPI events=%d  UFSS stored=%d" % (p.split("/")[-2], ebok, t_ebs or 0, hb, ring_cnt, stored))
    if last is not None and t_ebs:
        # Timer() = cntvct * 10 MHz / 19.2 MHz ... relative to counter start (same base on this SoC); compare mod 2^32 (429.5 s)
        t_last = (last / 1e7)
        t_e = t_ebs % 429.4967296
        print("  last UFSS stamp = %.2f s (mod 429.5)   EBS = %.2f s   => Windows ran ~%.1f s after EBS" % (t_last, t_e, (t_last - t_e) % 429.4967296))
