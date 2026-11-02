#!/usr/bin/env python3
"""usage: pe_strlist.py <pe.sys> [regex]  - list every adrp+add reference that resolves to a UTF-16 string, in code address order (shows the flow of registry/config parsing)"""
import sys, re, pefile
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
path = sys.argv[1]; rx = re.compile(sys.argv[2]) if len(sys.argv) > 2 else None
pe = pefile.PE(path); data = open(path, 'rb').read()
secs = [(s.VirtualAddress, max(s.Misc_VirtualSize, s.SizeOfRawData), s.PointerToRawData) for s in pe.sections]
def off(rva):
    for va, sz, po in secs:
        if va <= rva < va + sz: return po + rva - va
def ustr(rva):
    o = off(rva)
    if o is None: return None
    b = bytearray()
    for i in range(0, 400, 2):
        c = data[o + i:o + i + 2]
        if len(c) < 2 or c == b'\0\0': break
        if c[1] != 0 and not (0x20 <= c[0] <= 0x7e and c[1] == 0): return None
        b += c[:1]
    s = b.decode('latin1')
    return s if len(s) >= 3 and all(32 <= ord(ch) < 127 for ch in s) else None
md = Cs(CS_ARCH_ARM64, CS_MODE_ARM); md.skipdata = True
out = []
for s in pe.sections:
    nm = s.Name.rstrip(b'\0').decode()
    if nm not in ('.text', 'PAGE'): continue
    code = data[s.PointerToRawData:s.PointerToRawData + min(s.Misc_VirtualSize, s.SizeOfRawData)]
    insns = list(md.disasm(code, s.VirtualAddress))
    for k, ins in enumerate(insns):
        if ins.mnemonic == 'adrp':
            reg = ins.op_str.split(',')[0]; pg = int(ins.op_str.split('#')[1], 16)
            for j in range(k + 1, min(k + 6, len(insns))):
                p = [x.strip() for x in insns[j].op_str.split(',')]
                if insns[j].mnemonic == 'add' and len(p) == 3 and p[1] == reg and p[2].startswith('#'):
                    t = ustr(pg + int(p[2][1:], 16))
                    if t and (rx is None or rx.search(t)): out.append((ins.address, t))
                    break
for a, t in sorted(out): print(f'{a:08x}  {t}')
