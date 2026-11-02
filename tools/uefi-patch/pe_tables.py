#!/usr/bin/env python3
"""usage: pe_tables.py <pe.sys> <name> [name...] - find 64-bit absolute pointers to the UTF-16 strings and dump the surrounding table rows (shows how registry value names map to struct fields)"""
import sys, struct, pefile
path = sys.argv[1]; names = sys.argv[2:]
pe = pefile.PE(path); data = open(path, 'rb').read(); base = pe.OPTIONAL_HEADER.ImageBase
secs = [(s.Name.rstrip(b'\0').decode(), s.VirtualAddress, max(s.Misc_VirtualSize, s.SizeOfRawData), s.PointerToRawData) for s in pe.sections]
def rva_of(o):
    for n, va, sz, po in secs:
        if po <= o < po + sz: return va + o - po
def off_of(r):
    for n, va, sz, po in secs:
        if va <= r < va + sz: return po + r - va
def ustr_at(rva):
    o = off_of(rva); b = bytearray()
    if o is None: return None
    for i in range(0, 120, 2):
        c = data[o + i:o + i + 2]
        if len(c) < 2 or c == b'\0\0': break
        if c[1] != 0: return None
        b += c[:1]
    return b.decode('latin1')
for nm in names:
    pat = nm.encode('utf-16le') + b'\0\0'
    i = -1; found = False
    while True:
        i = data.find(pat, i + 1)
        if i < 0: break
        r = rva_of(i)
        if ustr_at(r) != nm: continue
        for ptr in (struct.pack('<Q', base + r), struct.pack('<I', r)):
            j = -1
            while True:
                j = data.find(ptr, j + 1)
                if j < 0: break
                found = True
                print(f'== {nm}: string rva {r:#x}, referenced at file {j:#x} (rva {rva_of(j):#x}) as {len(ptr)*8}-bit')
                for k in range(-4, 6):
                    q = j + k * 8
                    v = struct.unpack_from('<Q', data, q)[0]
                    s = ustr_at(v - base) if base <= v < base + 0x10000000 else None
                    print(f'   {rva_of(q):#08x}: {v:#018x}  {s if s else ""}')
    if not found: print(f'== {nm}: no pointer found')
