#!/usr/bin/env python3
"""Decode ACPI breadcrumbs + MuChain markers from a captured RAMCON.BIN.
usage: read_breadcrumbs.py RAMCON.BIN map.txt"""
import struct
import sys

d = open(sys.argv[1], "rb").read()
names = {}
for ln in open(sys.argv[2], encoding="utf-8"):
    p = ln.rstrip("\n").split("\t")
    if len(p) == 3:
        names[int(p[0], 16)] = "%s %s" % (p[1], p[2])
O = 0x1F0000
u32 = lambda off: struct.unpack_from("<I", d, O + off)[0]
print("MuChain markers: MUCM=%r EBS!=%r EBOK=%r" % (d[O+0x400:O+0x404], d[O+0x404:O+0x408], d[O+0x408:O+0x40C]))
svc, n = u32(0x420), u32(0x424)
print("last traced UEFI service code %d arg %d (calls %d)" % (svc >> 24, svc & 0xFFFFFF, n))
cnt = u32(0)
print("ACPI events total:", cnt)
print("per-event counters:")
for k in range(32):
    c = u32(0x84 + 4 * k)
    if c:
        print("  id=0x%02X  x%-4d %s" % (k, c, names.get(k, "?")))
print("last 32 events:")
n = min(cnt, 32)
t0 = None
for k in range(cnt - n, cnt):
    v = u32(4 + (k & 0x1F) * 4)
    ev, t = v & 0xFF, v >> 8
    if t0 is None:
        t0 = t
    print("%4d  +%8.3f ms  id=0x%02X  %s" % (k, ((t - t0) & 0xFFFFFF) * 1e-4, ev, names.get(ev, "?")))
