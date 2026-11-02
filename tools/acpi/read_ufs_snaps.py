#!/usr/bin/env python3
"""Decode the UFS HC register snapshots (instrument_ufs_regs.py) from a captured RAMCON.BIN.   usage: read_ufs_snaps.py RAMCON.BIN"""
import struct
import sys

d = open(sys.argv[1], "rb").read()
O = 0x1F2000
SLOT = 48
u = lambda off: struct.unpack_from("<I", d, O + off)[0]
calls, stored = u(0), u(4)
print("UFSS calls: %d   snapshots stored: %d (ring keeps the last 16)" % (calls, stored))
names = ["Timer", "HCE", "HCS", "IS", "IE", "UECPA", "UECDL", "UECN", "UECT", "UTRLBA", "UTRLBAU", "UTRLDBR", "UTRLRSR", "UICCMD", "UCMDARG1", "UCMDARG2"]
SCSI = {0x00: "TEST UNIT READY", 0x12: "INQUIRY", 0x1A: "MODE SENSE(6)", 0x25: "READ CAPACITY(10)", 0x28: "READ(10)", 0x2A: "WRITE(10)", 0x35: "SYNC CACHE(10)",
        0x1B: "START STOP UNIT", 0x9E: "SERVICE ACTION IN(16)", 0xA0: "REPORT LUNS", 0x88: "READ(16)", 0x8A: "WRITE(16)", 0x03: "REQUEST SENSE", 0x5A: "MODE SENSE(10)", 0x42: "UNMAP"}


def ext(v, base):
    slot = v[base]
    if slot == 0xFFFFFFFF:
        return "none"
    upiu0, upiu1, upiu2, c0, c1, c2 = v[base + 5:base + 11]
    typ, flags, lun, tag = upiu0 & 0xFF, (upiu0 >> 8) & 0xFF, (upiu0 >> 16) & 0xFF, (upiu0 >> 24) & 0xFF
    op = c0 & 0xFF
    return "slot %d: UTRD.DW0=%08X OCS=%02X ucd=%X%08X UPIU type=%02X flags=%02X lun=%02X tag=%02X len=%08X CDB=%02X(%s) %02X%02X%02X.." % (
        slot, v[base + 1], v[base + 2] & 0xFF, v[base + 4], v[base + 3], typ, flags, lun, tag, upiu2, op, SCSI.get(op, "?"),
        (c0 >> 8) & 0xFF, (c0 >> 16) & 0xFF, (c0 >> 24) & 0xFF)


first = max(0, stored - 16)
t0 = None
for k in range(first, stored):
    slot = k & 15
    v = [u(0x10 + slot * SLOT * 4 + 4 * i) for i in range(SLOT)]
    if t0 is None:
        t0 = v[0]
    print("#%d  t=+%8.1f ms  " % (k, ((v[0] - t0) & 0xFFFFFFFF) * 1e-4) + "  ".join("%s=%08X" % (n, x) for n, x in zip(names[1:], v[1:16]) if n in ("HCE", "HCS", "IS", "UTRLDBR", "UTRLBA", "UECDL", "UECN", "UECPA")))
    print("        lo:", ext(v, 16))
    print("        hi:", ext(v, 27))
