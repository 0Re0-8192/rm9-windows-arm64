#!/usr/bin/env python3
"""usage: pe_ustrlist.py <pe.sys> [lo hi]  - list code references to UNICODE_STRING constants (struct {u16 len,u16 max,pad,ptr}) in address order"""
import sys, struct, pefile
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
path = sys.argv[1]
lo = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0
hi = int(sys.argv[3], 16) if len(sys.argv) > 3 else 1 << 40
pe = pefile.PE(path); data = open(path, 'rb').read(); base = pe.OPTIONAL_HEADER.ImageBase
secs = [(s.Name.rstrip(b'\0').decode(), s.VirtualAddress, max(s.Misc_VirtualSize, s.SizeOfRawData), s.PointerToRawData, s.Misc_VirtualSize) for s in pe.sections]
def off(r):
    for n, va, sz, po, vs in secs:
        if va <= r < va + sz: return po + r - va
def us(r):
    o = off(r)
    if o is None or o + 16 > len(data): return None
    ln, mx, _, ptr = struct.unpack_from('<HHIQ', data, o)
    if ln == 0 or ln > mx or mx > 400 or not (base <= ptr < base + 0x1000000): return None
    so = off(ptr - base)
    if so is None: return None
    try: s = data[so:so + ln].decode('utf-16le')
    except Exception: return None
    return s if s.isprintable() and len(s) >= 2 else None
md = Cs(CS_ARCH_ARM64, CS_MODE_ARM); md.skipdata = True
rows = []
for n, va, sz, po, vs in secs:
    if n not in ('.text', 'PAGE'): continue
    insns = list(md.disasm(data[po:po + min(vs, sz)], va))
    for k, ins in enumerate(insns):
        if not (lo <= ins.address < hi): continue
        if ins.mnemonic == 'adrp':
            reg = ins.op_str.split(',')[0]; pg = int(ins.op_str.split('#')[1], 16)
            for j in range(k + 1, min(k + 5, len(insns))):
                p = [x.strip() for x in insns[j].op_str.split(',')]
                if insns[j].mnemonic == 'add' and len(p) == 3 and p[1] == reg and p[2].startswith('#'):
                    t = pg + int(p[2][1:], 16); s = us(t)
                    if s: rows.append((ins.address, s))
                    break
for a, s in rows: print(f'{a:08x}  {s}')
