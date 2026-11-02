p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()

old = 'STATIC UINT64  mSmmuPgd[4] __attribute__ ((aligned (64)));\n'
assert old in s
s = s.replace(old, '''// The stage-1 table must outlive MuChain: it is read by the SMMU while Windows runs, so it lives in EfiReservedMemoryType pages (a static array sits in boot-services memory that Windows reuses).
STATIC UINT64  *mSmmuPgd = NULL;
''', 1)

old = '  CbB = SMMU_CB_B + 0x1000ULL * Cb;\n'
assert old in s
s = s.replace(old, '''  if (mSmmuPgd == NULL) {
    EFI_PHYSICAL_ADDRESS  Pg = 0;
    if (EFI_ERROR (gBS->AllocatePages (AllocateAnyPages, EfiReservedMemoryType, 1, &Pg))) {
      PL ("SMMU: cannot allocate the reserved page for the stage-1 table%a", "@@NL@@");
      return FALSE;
    }
    SetMem ((VOID *)(UINTN)Pg, 4096, 0);
    mSmmuPgd = (UINT64 *)(UINTN)Pg;
    PL ("SMMU: stage-1 table at 0x%lx (reserved memory)%a", (UINT64)Pg, "@@NL@@");
  }
''' + old, 1)
s = s.replace('GeniCacheOp (mSmmuPgd, sizeof (mSmmuPgd));', 'GeniCacheOp (mSmmuPgd, 4 * sizeof (UINT64));', 1)
assert 'sizeof (mSmmuPgd)' not in s
s = s.replace('@@NL@@', chr(92) + 'n')
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
