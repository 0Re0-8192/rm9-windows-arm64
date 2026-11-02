"""Disassemble a function (or a window of it) from an arm64 kernel module.
usage: ko_disasm.py <file.ko> <symbol> [from_off] [to_off]   (offsets relative to the symbol, hex ok)"""
import sys

from capstone import CS_ARCH_ARM64, CS_MODE_ARM, Cs
from elftools.elf.elffile import ELFFile
from elftools.elf.relocation import RelocationSection

path, name = sys.argv[1], sys.argv[2]
lo = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0
hi = int(sys.argv[4], 0) if len(sys.argv) > 4 else None
f = ELFFile(open(path, "rb"))
symtab = f.get_section_by_name(".symtab")
sym = next(s for s in symtab.iter_symbols() if s.name == name and s["st_info"]["type"] == "STT_FUNC")
sec = f.get_section(sym["st_shndx"])
size = sym["st_size"]
hi = size if hi is None else min(hi, size)
data = sec.data()[sym["st_value"] + lo: sym["st_value"] + hi]
# relocations against this section (calls / data refs) for readability
rel = {}
for rs in f.iter_sections():
    if isinstance(rs, RelocationSection) and f.get_section(rs["sh_info"]) is sec:
        st = f.get_section(rs["sh_link"])
        for r in rs.iter_relocations():
            s = st.get_symbol(r["r_info_sym"])
            rel[r["r_offset"]] = s.name or f.get_section(s["st_shndx"]).name if s["st_shndx"] not in ("SHN_UNDEF", "SHN_ABS") else s.name
md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
print(f"{name}: section {sec.name}, value {sym['st_value']:#x}, size {size:#x}")
for i in md.disasm(data, sym["st_value"] + lo):
    off = i.address - sym["st_value"]
    r = rel.get(i.address)
    print(f"  +{off:#06x}  {i.mnemonic:8s} {i.op_str}" + (f"    ; -> {r}" if r else ""))
