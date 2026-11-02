#!/usr/bin/env python3
"""Show the NTFS volume flags (dirty bit etc.) of the phone's 'windows' partition by parsing MFT record 3 ($Volume) raw (run in WSL)."""
import struct
import sys
sys.path.insert(0, "<RM9_WORKDIR>/refs")
from ntfs_remote import Remote

fh = Remote()
fh.seek(0)
bs = fh.read(512)
bps, spc = struct.unpack_from("<HB", bs, 0x0B)
mft_lcn = struct.unpack_from("<Q", bs, 0x30)[0]
cs = bps * spc
rs = struct.unpack_from('<b', bs, 0x40)[0]
rs = (1 << -rs) if rs < 0 else rs * cs
print('bps', bps, 'spc', spc, 'mft_lcn', mft_lcn, 'rec size', rs)
fh.seek(mft_lcn * cs + 3 * rs)
rec = fh.read(rs)
assert rec[:4] == b"FILE", rec[:4]
# apply the update sequence array
usoff, usn = struct.unpack_from("<HH", rec, 4)
rec = bytearray(rec)
for i in range(1, usn):
    rec[i * 512 - 2:i * 512] = rec[usoff + 2 * i:usoff + 2 * i + 2]
off = struct.unpack_from("<H", rec, 0x14)[0]
while off < rs:
    typ, ln = struct.unpack_from("<II", rec, off)
    if typ == 0xFFFFFFFF:
        break
    if typ == 0x70:
        voff = struct.unpack_from("<H", rec, off + 0x14)[0]
        v = off + voff
        major, minor, flags = struct.unpack_from("<BBH", rec, v + 8)
        print("NTFS %d.%d flags=0x%04x dirty=%s resize_logfile=%s chkdsk_requested=%s" % (major, minor, flags, bool(flags & 1), bool(flags & 2), bool(flags & 0x80)))
    off += ln
