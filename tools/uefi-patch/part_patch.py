p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
BS = chr(92)
code = r'''// what PIL's partition lookup sees: protocol FE2555BE-D716-4686-B9D0-79DB5921B70D (a GPT-entry-like struct, name at +0x38) on BlockIo handles
STATIC VOID
PartProbe (VOID)
{
  STATIC EFI_GUID  FeGuid = { 0xFE2555BE, 0xD716, 0x4686, { 0xB9, 0xD0, 0x79, 0xDB, 0x59, 0x21, 0xB7, 0x0D } };
  EFI_HANDLE  *H = NULL;
  UINTN       N = 0, I, J, K, Fe = 0, Sfs = 0, Shown = 0;
  EFI_GUID    **Pr;
  UINTN       PrN;

  if (EFI_ERROR (gBS->LocateHandleBuffer (ByProtocol, &gEfiBlockIoProtocolGuid, NULL, &N, &H))) {
    return;
  }
  for (I = 0; I < N; I++) {
    BOOLEAN  HasFe = FALSE, HasSfs = FALSE;
    if (!EFI_ERROR (gBS->ProtocolsPerHandle (H[I], &Pr, &PrN))) {
      for (J = 0; J < PrN; J++) {
        if (CompareGuid (Pr[J], &FeGuid)) {
          HasFe = TRUE;
        }
        if (CompareGuid (Pr[J], &gEfiSimpleFileSystemProtocolGuid)) {
          HasSfs = TRUE;
        }
      }
      if (HasFe && Shown < 6) {
        VOID  *Ent = NULL;
        CHAR16  Name[24];
        if (!EFI_ERROR (gBS->HandleProtocol (H[I], &FeGuid, &Ent)) && Ent != NULL && *(VOID **)Ent != NULL) {
          CONST UINT16  *Nm = (CONST UINT16 *)((UINTN)(*(UINT64 *)Ent) + 0x38);
          for (K = 0; K < 23 && Nm[K] != 0; K++) {
            Name[K] = Nm[K];
          }
          Name[K] = 0;
          PL ("PART fe handle %p ent=%p name=%s sfs=%d\n", H[I], *(VOID **)Ent, Name, HasSfs);
        } else {
          PL ("PART fe handle %p struct=%p (raw[0..3]=%lx %lx %lx %lx)\n", H[I], Ent, Ent ? ((UINT64 *)Ent)[0] : 0, Ent ? ((UINT64 *)Ent)[1] : 0, Ent ? ((UINT64 *)Ent)[2] : 0, Ent ? ((UINT64 *)Ent)[3] : 0);
        }
        Shown++;
      }
      if (HasFe) {
        Fe++;
      }
      if (HasSfs) {
        Sfs++;
      }
      FreePool (Pr);
    }
  }
  PL ("PART blockio handles=%lu with FE2555BE=%lu with SFS=%lu\n", (UINT64)N, (UINT64)Fe, (UINT64)Sfs);
  FreePool (H);
}

'''
marker = '// ADSP.TXT + NOBOOT:'
assert marker in s
s = s.replace(marker, code + marker, 1)
old = '    AdspLoad ();'
assert old in s
s = s.replace(old, '    PartProbe ();\n' + old, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
