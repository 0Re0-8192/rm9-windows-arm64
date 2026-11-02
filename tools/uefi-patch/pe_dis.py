#!/usr/bin/env python3
"""usage: pe_dis.py <pe.sys> <lo_rva> <hi_rva>  - disassemble a range, annotating UNICODE_STRING constants and keeping only the interesting lines (string refs, calls, branches targets are kept short)"""
import sys, struct, pefile
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
path = sys.argv[1]; lo = int(sys.argv[2], 16); hi = int(sys.argv[3], 16)
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
imp = {}
try:
    for e in pe.DIRECTORY_ENTRY_IMPORT:
        for i in e.imports:
            if i.name: imp[i.address - base] = i.name.decode()
except Exception: pass
md = Cs(CS_ARCH_ARM64, CS_MODE_ARM); md.skipdata = True
for n, va, sz, po, vs in secs:
    if n not in ('.text', 'PAGE') or not (va <= lo < va + sz): continue
    insns = list(md.disasm(data[po:po + min(vs, sz)], va))
    note = {}
    for k, ins in enumerate(insns):
        if ins.mnemonic == 'adrp':
            reg = ins.op_str.split(',')[0]; pg = int(ins.op_str.split('#')[1], 16)
            for j in range(k + 1, min(k + 5, len(insns))):
                p = [x.strip() for x in insns[j].op_str.split(',')]
                if insns[j].mnemonic == 'add' and len(p) == 3 and p[1] == reg and p[2].startswith('#'):
                    s = us(pg + int(p[2][1:], 16))
                    if s: note[insns[j].address] = f'  ; "{s}"'
                    break
                if insns[j].mnemonic == 'ldr' and reg in insns[j].op_str:
                    q = insns[j].op_str.split('[')[1].rstrip(']').split(',')
                    if len(q) == 2 and q[1].strip().startswith('#'):
                        t = pg + int(q[1].strip()[1:], 16)
                        if t in imp: note[insns[j].address] = f'  ; import {imp[t]}'
                    break
    for ins in insns:
        if lo <= ins.address < hi:
            print(f'{ins.address:08x}  {ins.mnemonic:7s} {ins.op_str}{note.get(ins.address, "")}')
