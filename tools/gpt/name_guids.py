#!/usr/bin/env python3
"""usage: name_guids.py <efi> - take 16-byte-aligned GUID-looking blocks of .data, resolve names from the Mu-Silicium .dec / .h files"""
import sys, struct, subprocess, re, os
import pefile
path = sys.argv[1]
pe = pefile.PE(path); data = open(path, 'rb').read()
cands = []
for s in pe.sections:
    n = s.Name.rstrip(b'\0').decode()
    if n not in ('.data', '.rdata'): continue
    po, sz = s.PointerToRawData, s.SizeOfRawData
    for off in range(po + ((8 - (s.VirtualAddress % 8)) % 8), po + sz - 16, 8):
        d1, d2, d3 = struct.unpack_from('<IHH', data, off); d4 = data[off + 8:off + 16]
        if d1 < 0x10000 or d2 == 0 or d3 == 0 or d4 == b'\0' * 8: continue
        if (d3 >> 12) not in (1, 2, 3, 4, 5): continue
        cands.append((s.VirtualAddress + off - po, d1, d2, d3, d4))
seen = set()
for rva, d1, d2, d3, d4 in cands:
    key = (d1, d2, d3, d4)
    if key in seen: continue
    seen.add(key)
    pat = f'0x{d1:08X}'
    r = subprocess.run(['grep', '-rIi', '-m1', '--include=*.dec', '--include=*.h', pat, '/root/Mu-Silicium/Silicon', '/root/Mu-Silicium/Mu_Basecore/MdePkg', '/root/Mu-Silicium/Mu_Basecore/MdeModulePkg', '/root/Mu-Silicium/Common'], capture_output=True, text=True)
    line = r.stdout.strip().split('\n')[0][:120] if r.stdout.strip() else ''
    nm = re.search(r'(g\w+Guid)', line)
    print(f'rva={rva:#x} {{{d1:08X}-{d2:04X}-{d3:04X}-{d4[:2].hex().upper()}-{d4[2:].hex().upper()}}} {nm.group(1) if nm else "(unknown)"}')
