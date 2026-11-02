"""Find the AArch64 functions in a PE image that reference given strings (ADRP+ADD/LDR pairs). usage: pe_xref.py image.efi 'substr1' 'substr2' ..."""
import struct
import sys

path = sys.argv[1]
needles = [s.encode() for s in sys.argv[2:]]
d = open(path, "rb").read()
pe = struct.unpack_from("<I", d, 0x3C)[0]
nsec = struct.unpack_from("<H", d, pe + 6)[0]
opt = pe + 24
optsz = struct.unpack_from("<H", d, pe + 20)[0]
imgbase = struct.unpack_from("<Q", d, opt + 24)[0]
secs = []
for i in range(nsec):
    o = opt + optsz + 40 * i
    name = d[o:o + 8].rstrip(b"\0").decode()
    vsz, va, rsz, roff = struct.unpack_from("<IIII", d, o + 8)
    secs.append((name, va, vsz, roff, rsz))
print("imagebase", hex(imgbase), [(s[0], hex(s[1]), hex(s[2])) for s in secs])


def rva_to_off(rva):
    for n, va, vsz, roff, rsz in secs:
        if va <= rva < va + max(vsz, rsz):
            return roff + rva - va
    return None


def off_to_rva(off):
    for n, va, vsz, roff, rsz in secs:
        if roff <= off < roff + rsz:
            return va + off - roff
    return None


targets = {}
for nd in needles:
    start = 0
    while True:
        i = d.find(nd, start)
        if i < 0:
            break
        # extend to the start of the string
        j = i
        while j > 0 and d[j - 1] != 0:
            j -= 1
        targets[off_to_rva(j)] = d[j:d.find(b"\0", j)].decode(errors="replace")
        start = i + 1
print("string RVAs:", {hex(k): v[:70] for k, v in targets.items()})
text = [s for s in secs if s[0] in (".text", "text") or s[0].startswith(".text")]
refs = []
for n, va, vsz, roff, rsz in secs:
    if n not in (".text",):
        continue
    for off in range(roff, roff + rsz - 8, 4):
        w = struct.unpack_from("<I", d, off)[0]
        if (w & 0x9F000000) == 0x90000000:  # ADRP
            rd = w & 31
            immlo = (w >> 29) & 3
            immhi = (w >> 5) & 0x7FFFF
            imm = ((immhi << 2) | immlo) << 12
            if imm & (1 << 32):
                imm -= 1 << 33
            pc = va + off - roff
            page = (pc & ~0xFFF) + imm
            # look ahead 1..4 words for ADD rd,rd,#imm12
            for k in range(1, 5):
                w2 = struct.unpack_from("<I", d, off + 4 * k)[0]
                if (w2 & 0xFFC00000) == 0x91000000 and ((w2 >> 5) & 31) == rd:
                    full = page + ((w2 >> 10) & 0xFFF)
                    if full in targets:
                        refs.append((pc, targets[full]))
                    break
for pc, s in refs:
    # walk back to a likely function start (stp x29,x30,[sp,#-N]! or sub sp,sp,#N) within 0x400 bytes
    off = rva_to_off(pc)
    fs = None
    for k in range(0, 0x600, 4):
        w = struct.unpack_from("<I", d, off - k)[0]
        if (w & 0xFFC003E0) == 0xA98003E0 or (w & 0xFF0003FF) == 0xD10003FF:   # stp pre-index with sp / sub sp,sp,#imm
            fs = pc - k
            break
    print("ref at RVA %#x -> %r ; probable function start %s" % (pc, s[:60], hex(fs) if fs else "?"))
