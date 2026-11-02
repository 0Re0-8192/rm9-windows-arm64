"""MuChain: set UFS fPowerOnWPEn (write-protect LUN1-4) right before ExitBootServices, unless \\NOWP.TXT exists."""
from pathlib import Path

c = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = c.read_text(encoding="utf-8")
assert "mNoWp" not in t

# forward declaration + state next to mNoBoot
t = t.replace("STATIC BOOLEAN      mNoBoot     = TRUE;",
              "STATIC BOOLEAN      mNoWp       = FALSE;  // \\NOWP.TXT present: do not set fPowerOnWPEn at EBS\n"
              "STATIC BOOLEAN      mNoBoot     = TRUE;", 1)
t = t.replace("#include <Guid/FileInfo.h>\n",
              "#include <Guid/FileInfo.h>\n\n"
              "STATIC EFI_STATUS UfsQueryFlag (IN UINT64 Base, IN UINT8 Opcode, IN UINT8 Idn, OUT UINT8 *Val, OUT UINT8 *RespCode);\n", 1)

old = "  DumpHookStats (\"at-EBS\");\n  gBS->ExitBootServices = mOrigExitBs;"
assert old in t
new = '''  DumpHookStats ("at-EBS");
  if (!mNoWp) {
    // C: write-protect LUN1-4 (boot chain) until the next power cycle; the UFS device clears it on reset.
    UINT8      V1 = 0xFF, R1 = 0xFF, V2 = 0xFF, R2 = 0xFF;
    EFI_STATUS Q1 = UfsQueryFlag (0x1D84000ULL, 6, 3, &V1, &R1);
    EFI_STATUS Q2 = UfsQueryFlag (0x1D84000ULL, 5, 3, &V2, &R2);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] EBS: SET_FLAG fPowerOnWPEn %r (qresp 0x%x), READ_FLAG %r flag=%u\\n", Q1, R1, Q2, V2));
    *(volatile UINT32 *)(UINTN)0xD7FF042CULL = 0x57500000U | ((UINT32)V2 << 8) | (UINT32)(EFI_ERROR (Q1) ? 1 : 0);   // "WP" + flag
  } else {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] EBS: NOWP.TXT present, fPowerOnWPEn NOT set\\n"));
  }
  gBS->ExitBootServices = mOrigExitBs;'''
t = t.replace(old, new, 1)

old2 = "  mNoBoot = !SelfFileExists (L\"\\\\BOOTOK.TXT\") || SelfFileExists (L\"\\\\NOBOOT.TXT\");"
assert old2 in t
t = t.replace(old2, old2 + "\n  mNoWp   = SelfFileExists (L\"\\\\NOWP.TXT\");", 1)
# UCD buffer must be allocated BEFORE bootmgfw starts: an allocation inside the EBS hook would change the memory map and
# invalidate the MapKey winload passes in.  Make it file-scope and refuse to allocate from the EBS hook.
assert "  STATIC EFI_PHYSICAL_ADDRESS  Ucd = 0;\n" in t
t = t.replace("  STATIC EFI_PHYSICAL_ADDRESS  Ucd = 0;\n", "", 1)
t = t.replace("STATIC EFI_STATUS UfsQueryFlag (IN UINT64 Base, IN UINT8 Opcode, IN UINT8 Idn, OUT UINT8 *Val, OUT UINT8 *RespCode);\n",
              "STATIC EFI_STATUS UfsQueryFlag (IN UINT64 Base, IN UINT8 Opcode, IN UINT8 Idn, OUT UINT8 *Val, OUT UINT8 *RespCode);\n"
              "STATIC EFI_PHYSICAL_ADDRESS mUfsUcd = 0;   // DMA buffer for UFS queries, allocated early (see UfsQueryFlag)\n", 1)
t = t.replace("  if (Ucd == 0) {\n    Ucd = 0xFFFFFFFFULL;\n    S = gBS->AllocatePages (AllocateMaxAddress, EfiBootServicesData, 1, &Ucd);\n    if (EFI_ERROR (S)) {\n      Ucd = 0;\n      return S;\n    }\n  }\n",
              "  if (mUfsUcd == 0) {\n    if (mInEbs) {\n      return EFI_NOT_READY;   // never allocate inside the EBS hook\n    }\n    mUfsUcd = 0xFFFFFFFFULL;\n    S = gBS->AllocatePages (AllocateMaxAddress, EfiBootServicesData, 1, &mUfsUcd);\n    if (EFI_ERROR (S)) {\n      mUfsUcd = 0;\n      return S;\n    }\n  }\n  Ucd = mUfsUcd;\n", 1)
t = t.replace("  UINT64                       Utrl;\n  volatile UINT32              *Trd;", "  EFI_PHYSICAL_ADDRESS         Ucd;\n  UINT64                       Utrl;\n  volatile UINT32              *Trd;", 1)
assert "mUfsUcd == 0" in t and "EFI_PHYSICAL_ADDRESS         Ucd;" in t
c.write_text(t, encoding="utf-8")
print("ok")
