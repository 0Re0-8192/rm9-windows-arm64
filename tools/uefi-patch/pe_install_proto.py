#!/usr/bin/env python3
"""usage: pe_install_proto.py <efi> - list the GUID constants stored in .data/.rdata (16-byte aligned candidates referenced by InstallProtocolInterface) and print the function-pointer tables next to them"""
import sys, struct, pefile
path = sys.argv[1]
pe = pefile.PE(path); data = open(path, 'rb').read(); base = pe.OPTIONAL_HEADER.ImageBase
secs = [(s.Name.rstrip(b'\0').decode(), s.VirtualAddress, max(s.Misc_VirtualSize, s.SizeOfRawData), s.PointerToRawData) for s in pe.sections]
print([(n, hex(va), hex(sz)) for n, va, sz, po in secs])
def guid_at(o):
    d1, d2, d3 = struct.unpack_from('<IHH', data, o); d4 = data[o + 8:o + 16]
    return f'{{{d1:08X}-{d2:04X}-{d3:04X}-{d4[:2].hex().upper()}-{d4[2:].hex().upper()}}}'
# known GUIDs we look for
known = {
 'UsbDevice': (0xD9D9CE48, 0x44B8, 0x4F49), 'UsbfnIo': (0x32D2963A, 0xFE5D, 0x4F30),
}
# print every 8-byte aligned 16-byte block in .data/.rdata that looks like a GUID followed by a pointer table (heuristic: the 8 bytes after are not a pointer)
for n, va, sz, po in secs:
    if n not in ('.data', '.rdata'): continue
    for off in range(po, po + sz - 16, 4):
        d1, d2, d3 = struct.unpack_from('<IHH', data, off)
        if d1 in (0, 0xFFFFFFFF) or d1 < 0x1000: continue
        # GUID heuristic: d2,d3 non-zero and the clock-seq/node bytes not all zero
        d4 = data[off + 8:off + 16]
        if d2 == 0 or d3 == 0 or d4 == b'\0' * 8: continue
        if (d3 >> 12) not in (1, 2, 3, 4, 5, 0xA, 0xB) and d3 < 0x100: continue
        print(f'{n} rva={va + off - po:#x} {guid_at(off)}')
