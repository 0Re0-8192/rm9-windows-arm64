#!/usr/bin/env python3
"""Run in WSL after build_lun_replicas.py: make every partition's unique GUID distinct across the replica LUNs
(lun N, entry i -> bytes_le starts with N<<8|i+1 ... ), fixing entry-array and header CRCs of primary and backup."""
import struct, sys, zlib
S = 4096
LUNS = [int(a) for a in sys.argv[1:]] or range(6)
for n in LUNS:
    with open("/root/qemu/lun%d.img" % n, "r+b") as f:
        f.seek(S); h = bytearray(f.read(92))
        alt = struct.unpack_from("<Q", h, 32)[0]
        nent, esz = struct.unpack_from("<II", h, 80)
        f.seek(S * 2); ents = bytearray(f.read(nent * esz))
        for i in range(nent):
            e = ents[i * esz:(i + 1) * esz]
            if e[:16] == b"\0" * 16:
                continue
            ents[i * esz + 16:i * esz + 20] = struct.pack("<I", 0x52000000 | (n << 12) | (i + 1))
        ecrc = zlib.crc32(bytes(ents)) & 0xFFFFFFFF
        f.seek(S * 2); f.write(ents)
        for lba in (1, alt):
            f.seek(lba * S); hh = bytearray(f.read(92))
            struct.pack_into("<I", hh, 88, ecrc)
            hh[16:20] = b"\0\0\0\0"
            struct.pack_into("<I", hh, 16, zlib.crc32(bytes(hh)) & 0xFFFFFFFF)
            if lba == alt:
                bent = struct.unpack_from("<Q", hh, 72)[0]
                f.seek(bent * S); f.write(ents)
            f.seek(lba * S); f.write(hh)
print("partition GUIDs made unique")
