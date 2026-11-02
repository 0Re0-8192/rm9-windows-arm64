p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
bs = chr(92)
code = r'''// IPCCDxe runtime structures (image base 0xD213D000 in the current layout): the ISR is image+0x2A9C(cfg); per-protocol entries (32 B) at image+0x7670.
STATIC VOID
IpccDxeDump (VOID)
{
  UINT64  B = 0xD213D000ULL;
  UINT32  I, J;

  if (*(UINT16 *)(UINTN)B != 0x5A4D) {
    PL ("IPCCDxe dump: no MZ at 0x%lx" BSN, B);
    return;
  }
  for (I = 0; I < 8; I++) {
    UINT64  *E = (UINT64 *)(UINTN)(B + 0x7670 + 0x20 * I);
    PL ("IPCCDxe entry[%u]: %016lx %016lx %016lx %016lx" BSN, I, E[0], E[1], E[2], E[3]);
    for (J = 0; J < 4; J++) {
      UINT64  V = E[J];
      if (V > 0x80000000ULL && V < 0x100000000ULL && (V & 7) == 0) {
        UINT64  *Q = (UINT64 *)(UINTN)V;
        PL ("  e[%u][%u]->%lx: %016lx %016lx %016lx %016lx %016lx %016lx" BSN, I, J, V, Q[0], Q[1], Q[2], Q[3], Q[4], Q[5]);
      }
    }
  }
}

'''.replace(' BSN', bs + 'n"').replace('"' + bs + 'n"', bs + 'n"')
marker = '// ADSP.TXT + NOBOOT:'
assert marker in s and 'IpccDxeDump' not in s
s = s.replace(marker, code + marker, 1)
old = '  IpccIsrReport ("end");\n}'
assert old in s
s = s.replace(old, '  IpccIsrReport ("end");\n  IpccDxeDump ();\n}', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
