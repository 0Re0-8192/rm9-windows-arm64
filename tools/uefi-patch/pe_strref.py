#!/usr/bin/env python3
"""usage: pe_strref.py <pe.sys> <utf16 string> [ninsn]  - find the string in a PE (ARM64) and disassemble code that references it (ADRP+ADD)"""
import sys, struct
import pefile
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM

path, needle = sys.argv[1], sys.argv[2]
n = int(sys.argv[3]) if len(sys.argv) > 3 else 60
pe = pefile.PE(path)
data = open(path, 'rb').read()
base = pe.OPTIONAL_HEADER.ImageBase
pat = needle.encode('utf-16le')
secs = [(s.Name.rstrip(b'\0').decode(), s.VirtualAddress, s.Misc_VirtualSize, s.PointerToRawData, s.SizeOfRawData) for s in pe.sections]
def rva_of(off):
    for _, va, vs, po, ps in secs:
        if po <= off < po + ps:
            return va + off - po
def off_of(rva):
    for _, va, vs, po, ps in secs:
        if va <= rva < va + max(vs, ps):
            return po + rva - va
targets = []
i = -1
while True:
    i = data.find(pat, i + 1)
    if i < 0: break
    targets.append(rva_of(i))
print('string rvas', [hex(t) for t in targets if t])
# UNICODE_STRING { USHORT Length, MaximumLength; PWSTR Buffer } stored in data: look for 8-byte pointers to the string, struct starts 8 bytes earlier
extra = []
for t in list(targets):
    if not t: continue
    ptr = struct.pack('<Q', base + t)
    k = -1
    while True:
        k = data.find(ptr, k + 1)
        if k < 0: break
        r = rva_of(k)
        if r: extra.append(r - 8)
print('unicode_string struct rvas', [hex(x) for x in extra])
targets = [t for t in targets if t] + extra
md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
md.skipdata = True
text = [s for s in secs if s[0] in ('.text', 'PAGE')]
hits = []
for name, va, vs, po, ps in text:
    code = data[po:po + min(vs, ps)]
    insns = list(md.disasm(code, va))
    for k, ins in enumerate(insns):
        if ins.mnemonic == 'adr':
            tgt = int(ins.op_str.split('#')[1], 16)
            if tgt in targets:
                hits.append((name, k, insns))
        if ins.mnemonic == 'adrp':
            # adrp xN, page ; next insns add xN, xN, #off
            page = int(ins.op_str.split('#')[1], 16)
            reg = ins.op_str.split(',')[0]
            for j in range(k + 1, min(k + 4, len(insns))):
                m = insns[j]
                parts = [x.strip() for x in m.op_str.split(',')]
                if m.mnemonic == 'add' and len(parts) == 3 and parts[1] == reg and parts[2].startswith('#'):
                    tgt = page + int(parts[2][1:], 16)
                    if tgt in targets:
                        hits.append((name, k, insns))
print('refs', len(hits))
for name, k, insns in hits[:2]:
    print('==== code ref in', name, hex(insns[k].address))
    for ins in insns[max(0, k - 12):k + n]:
        print(f'{ins.address:08x}  {ins.mnemonic:8s} {ins.op_str}')
