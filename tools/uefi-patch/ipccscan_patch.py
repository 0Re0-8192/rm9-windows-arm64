p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
bs = chr(92)
code = r'''// find IPCCDxe's per-instance cfg (ISR argument): u64 at +0x10 is the register base (inside the IPCC window 0x400000-0x410000)
STATIC VOID
IpccCfgScan (VOID)
{
  UINT64  P, Hits = 0;
  UINT32  I;

  for (P = 0xCF000000ULL; P < 0xD2A00000ULL && Hits < 12; P += 8) {
    UINT64  V = *(UINT64 *)(UINTN)(P + 0x10);
    UINT16  Id = *(UINT16 *)(UINTN)(P + 6);
    if (V >= 0x400000ULL && V < 0x410000ULL && (Id == 229 || Id == 261 || Id == 0x105 || Id == 0xE5)) {
      PL ("IPCC cfg candidate @%lx (id16@+6=%u):" BSN, P, Id);
      for (I = 0; I < 8; I++) {
        PL ("   +%02x: %016lx" BSN, I * 8, *(UINT64 *)(UINTN)(P + I * 8));
      }
      Hits++;
    }
  }
  PL ("IPCC cfg scan done, hits=%lu" BSN, Hits);
}

'''.replace(' BSN', bs + 'n"').replace('"' + bs + 'n"', bs + 'n"')
marker = '// ADSP.TXT + NOBOOT:'
assert marker in s and 'IpccCfgScan' not in s
s = s.replace(marker, code + marker, 1)
s = s.replace('STATIC VOID IpccDxeDump (VOID);\n', 'STATIC VOID IpccDxeDump (VOID);\nSTATIC VOID IpccCfgScan (VOID);\n', 1)
old = '  IpccDxeDump ();\n}'
assert old in s
s = s.replace(old, '  IpccDxeDump ();\n  IpccCfgScan ();\n}', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
