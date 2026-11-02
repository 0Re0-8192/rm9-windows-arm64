"""MuChain: UfsHighDmaTest - READ_FLAG with the UCD (command + response UPIU) placed above 4 GB, to see whether the UFS HC can DMA there."""
from pathlib import Path

c = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = c.read_text(encoding="utf-8")
assert "UfsHighDmaTest" not in t
fn = r'''
STATIC VOID
UfsHighDmaTest (IN UINT64 Base)
{
  STATIC CONST UINT64  Max[] = { 0x1FFFFFFFFULL, 0x3FFFFFFFFULL, 0x7FFFFFFFFULL, 0xAFFFFFFFFULL };
  UINTN                K;

  for (K = 0; K < ARRAY_SIZE (Max); K++) {
    EFI_PHYSICAL_ADDRESS  High = Max[K];
    EFI_PHYSICAL_ADDRESS  Save = mUfsUcd;
    EFI_STATUS            S, Q;
    UINT8                 V = 0xFF, R = 0xFF;

    S = gBS->AllocatePages (AllocateMaxAddress, EfiBootServicesData, 1, &High);
    if (EFI_ERROR (S) || High < 0x100000000ULL) {
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] HIGHDMA max=0x%lx: no page above 4GB (%r, got 0x%lx)\n", Max[K], S, (UINT64)High));
      if (!EFI_ERROR (S)) { gBS->FreePages (High, 1); }
      continue;
    }
    mUfsUcd = High;
    Q = UfsQueryFlag (Base, 5, 3, &V, &R);
    mUfsUcd = Save;
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] HIGHDMA ucd=0x%lx: READ_FLAG %r flag=%u qresp=0x%x\n", (UINT64)High, Q, V, R));
    if (Q == EFI_TIMEOUT) {
      // do not touch the controller any more after a DMA timeout; leave the page allocated
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] HIGHDMA: timeout -> stop testing\n"));
      return;
    }
    gBS->FreePages (High, 1);
  }
}
'''
t = t.replace("\nSTATIC VOID\nUfsProbeOne (", fn + "\nSTATIC VOID\nUfsProbeOne (", 1)
old = '        DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSQ fPowerOnWPEn   : %r flag=%u qresp=0x%x\\n", Q, V, R));\n'
assert old in t
t = t.replace(old, old + "        if (mNoBoot) {\n          UfsHighDmaTest (Base);   // diagnostics only in safe (NOBOOT) mode\n        }\n", 1)
c.write_text(t, encoding="utf-8")
print("ok")
