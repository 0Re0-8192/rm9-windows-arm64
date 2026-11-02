#!/usr/bin/env python3
"""usage: pe_refs_rva.py <efi> <rva> [nbefore nafter]  - disassemble around every adrp+add that resolves to <rva> (ARM64 PE, RVA based)"""
import sys, pefile
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
path = sys.argv[1]; target = int(sys.argv[2], 16)
nb = int(sys.argv[3]) if len(sys.argv) > 3 else 6; na = int(sys.argv[4]) if len(sys.argv) > 4 else 24
pe = pefile.PE(path); data = open(path, 'rb').read()
md = Cs(CS_ARCH_ARM64, CS_MODE_ARM); md.skipdata = True
for s in pe.sections:
    if s.Name.rstrip(b'\0').decode() != '.text': continue
    ins = list(md.disasm(data[s.PointerToRawData:s.PointerToRawData + min(s.Misc_VirtualSize, s.SizeOfRawData)], s.VirtualAddress))
    for k, i in enumerate(ins):
        if i.mnemonic != 'adrp': continue
        reg = i.op_str.split(',')[0]; pg = int(i.op_str.split('#')[1], 16)
        for j in range(k + 1, min(k + 4, len(ins))):
            p = [x.strip() for x in ins[j].op_str.split(',')]
            if ins[j].mnemonic == 'add' and len(p) == 3 and p[1] == reg and p[2].startswith('#') and pg + int(p[2][1:], 16) == target:
                print(f'==== ref at {i.address:#x}')
                for m in ins[max(0, k - nb):k + na]:
                    print(f'{m.address:08x}  {m.mnemonic:7s} {m.op_str}')
                break
