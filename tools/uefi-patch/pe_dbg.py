import sys, struct, pefile
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
path = sys.argv[1]; want = int(sys.argv[2], 16)   # rva of the string
pe = pefile.PE(path); data = open(path, 'rb').read()
md = Cs(CS_ARCH_ARM64, CS_MODE_ARM); md.skipdata = True
for s in pe.sections:
    nm = s.Name.rstrip(b'\0').decode()
    if nm not in ('.text', 'PAGE'): continue
    code = data[s.PointerToRawData:s.PointerToRawData + min(s.Misc_VirtualSize, s.SizeOfRawData)]
    n = 0; near = 0
    for ins in md.disasm(code, s.VirtualAddress):
        if ins.mnemonic == 'adrp':
            n += 1
            pg = int(ins.op_str.split('#')[1], 16)
            if abs(pg - (want & ~0xfff)) < 0x2000: near += 1
    print(nm, 'adrp count', n, 'near target page', near)
    first = list(md.disasm(code[:64], s.VirtualAddress))[:6]
    print([ (hex(i.address), i.mnemonic, i.op_str) for i in first])
