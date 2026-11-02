"""MuChain: add UfsProbe() - read-only look at the UFS host controller (UFSHCI at 0x1D84000).
Checks the GCD first and only touches MMIO that the firmware already mapped.  No writes, no queries."""
from pathlib import Path

R = Path(r"<RM9_WORKDIR>\refs")
c = R / "MuChain.c"
i = R / "MuChain.inf"
t = c.read_text(encoding="utf-8")
if "UfsProbe" not in t:
    t = t.replace("#include <Library/PrintLib.h>\n",
                  "#include <Library/PrintLib.h>\n#include <Library/DxeServicesTableLib.h>\n", 1)
    fn = r'''
STATIC VOID
UfsProbeOne (IN UINT64 Base, IN UINTN Len, IN BOOLEAN Regs)
{
  EFI_GCD_MEMORY_SPACE_DESCRIPTOR  D;
  EFI_STATUS                       S;

  S = gDS->GetMemorySpaceDescriptor (Base, &D);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSPROBE gcd 0x%lx: %r type=%d attr=0x%lx base=0x%lx len=0x%lx\n",
          Base, S, S == EFI_SUCCESS ? (INT32)D.GcdMemoryType : -1, S == EFI_SUCCESS ? D.Attributes : 0,
          S == EFI_SUCCESS ? D.BaseAddress : 0, S == EFI_SUCCESS ? D.Length : 0));
  if (EFI_ERROR (S) || D.GcdMemoryType != EfiGcdMemoryTypeMemoryMappedIo || !Regs) {
    return;
  }
  {
    // standard UFSHCI register file (read-only)
    STATIC CONST struct { UINT32 Off; CONST CHAR8 *Name; } Reg[] = {
      { 0x00, "CAP" }, { 0x08, "VER" }, { 0x10, "HCDDID" }, { 0x14, "HCPMID" }, { 0x20, "IS" }, { 0x24, "IE" },
      { 0x30, "HCS" }, { 0x34, "HCE" }, { 0x38, "UECPA" }, { 0x3C, "UECDL" }, { 0x40, "UECN" }, { 0x44, "UECT" },
      { 0x48, "UECDME" }, { 0x4C, "UTRIACR" }, { 0x50, "UTRLBA" }, { 0x54, "UTRLBAU" }, { 0x58, "UTRLDBR" },
      { 0x5C, "UTRLCLR" }, { 0x60, "UTRLRSR" }, { 0x64, "UTRLCNR" }, { 0x70, "UTMRLBA" }, { 0x74, "UTMRLBAU" },
      { 0x78, "UTMRLDBR" }, { 0x80, "UTMRLRSR" }, { 0x90, "UICCMD" }, { 0x94, "UCMDARG1" }, { 0x98, "UCMDARG2" },
      { 0x9C, "UCMDARG3" },
    };
    UINTN K;
    for (K = 0; K < ARRAY_SIZE (Reg); K++) {
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSHC %-8a [0x%02x] = 0x%08x\n", Reg[K].Name, Reg[K].Off,
              *(volatile UINT32 *)(UINTN)(Base + Reg[K].Off)));
    }
  }
}

STATIC VOID
UfsProbe (VOID)
{
  UfsProbeOne (0x1D84000ULL, 0x15000, TRUE);    // UFS HC (DSDT UFS0: MMIO 0x1D84000 len 0x15000)
  UfsProbeOne (0x1D87000ULL, 0x1000,  FALSE);   // UFS PHY area, descriptor only
  UfsProbeOne (0x1D90000ULL, 0x1000,  FALSE);   // UFS ICE area, descriptor only
}
'''
    t = t.replace("STATIC VOID\nDumpProtocolsOnDisks (VOID)", fn + "\nSTATIC VOID\nDumpProtocolsOnDisks (VOID)", 1)
    t = t.replace("  DumpProtocolsOnDisks ();\n  if (SelfFileExists", "  DumpProtocolsOnDisks ();\n  UfsProbe ();\n  if (SelfFileExists", 1)
    c.write_text(t, encoding="utf-8")
s = i.read_text(encoding="utf-8")
if "DxeServicesTableLib" not in s:
    s = s.replace("  ArmSmcLib\n", "  ArmSmcLib\n  DxeServicesTableLib\n", 1)
    i.write_text(s, encoding="utf-8")
print("ok", "UfsProbe ();" in c.read_text(encoding="utf-8"))
