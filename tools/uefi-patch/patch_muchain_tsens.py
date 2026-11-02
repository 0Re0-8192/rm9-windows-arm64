"""MuChain: TsensProbe() - read-only dump of the three TSENS TM status blocks (0xC228000/0xC229000/0xC22A000).
Layout assumption (Linux tsens-v2): sensor n status at +0xA0+4n: bits[11:0] = signed temperature in deci-degC, bit21 = valid."""
from pathlib import Path

c = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = c.read_text(encoding="utf-8")
assert "TsensProbe" not in t
fn = r'''
STATIC VOID
TsensProbe (VOID)
{
  STATIC CONST UINT64  Base[3] = { 0xC228000ULL, 0xC229000ULL, 0xC22A000ULL };
  UINTN                C, N;

  for (C = 0; C < 3; C++) {
    EFI_GCD_MEMORY_SPACE_DESCRIPTOR  D;
    EFI_STATUS                       S = gDS->GetMemorySpaceDescriptor (Base[C], &D);
    if (EFI_ERROR (S) || D.GcdMemoryType != EfiGcdMemoryTypeMemoryMappedIo) {
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] TSENS%u 0x%lx: not mapped as MMIO (%r type=%d)\n", (UINT32)C, Base[C], S, S == EFI_SUCCESS ? (INT32)D.GcdMemoryType : -1));
      continue;
    }
    for (N = 0; N < 16; N++) {
      UINT32 V = *(volatile UINT32 *)(UINTN)(Base[C] + 0xA0 + 4 * N);
      INT32  T = (INT32)(V & 0xFFF);
      if (T & 0x800) {
        T -= 0x1000;
      }
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] TSENS%u sensor %2u: raw=0x%08x temp=%d.%u C valid=%u\n", (UINT32)C, (UINT32)N, V, T / 10, (UINT32)((T < 0 ? -T : T) % 10), (V >> 21) & 1));
    }
  }
}
'''
t = t.replace("\nSTATIC VOID\nDumpMemMap (VOID)", fn + "\nSTATIC VOID\nDumpMemMap (VOID)", 1)
old = "  UfsProbe ();\n"
assert old in t
t = t.replace(old, old + "  TsensProbe ();\n", 1)
c.write_text(t, encoding="utf-8")
print("ok")
