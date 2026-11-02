p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
BS = chr(92)
code = r'''// ADSP.TXT + NOBOOT: load the ADSP the way QcomChargerDxe does (PIL protocol fn1 = ProcessPilImage(CHAR16 *Name), config uefipil.cfg FULL_ADSP + FULL_ADSP_DTB from the modem partition)
typedef UINTN (EFIAPI *MC_PIL_LOAD) (CONST CHAR16 *Name);

STATIC VOID
AdspLoad (VOID)
{
  STATIC EFI_GUID  Guid = { 0x1F4F1DA3, 0x4D8D, 0x4894, { 0xBA, 0x2A, 0x13, 0xD3, 0x20, 0x7F, 0x97, 0x39 } };
  UINT64      *P = NULL;
  EFI_STATUS  St;
  UINTN       R;
  UINT64      T0;

  St = gBS->LocateProtocol (&Guid, NULL, (VOID **)&P);
  PL ("LocateProtocol(PIL) -> %r P=%p revision 0x%lx fn1=%p\n", St, P, P ? P[0] : 0, P ? (VOID *)P[1] : NULL);
  if (EFI_ERROR (St) || P == NULL) {
    return;
  }
  T0 = PcNowUs ();
  R = ((MC_PIL_LOAD)P[1]) (L"FULL_ADSP");
  PL ("ProcessPilImage(FULL_ADSP) -> 0x%lx in %lu ms\n", (UINT64)R, (PcNowUs () - T0) / 1000);
}

'''
marker = '// USBPWR.TXT + NOBOOT:'
assert marker in s
s = s.replace(marker, code + marker, 1)
old = '  PL ("=== UsbPwrCtrl probe' + BS + 'n");'
assert old in s
s = s.replace(old, old + '\n  if (SelfFileExists (L"' + BS * 2 + 'ADSP.TXT")) {\n    AdspLoad ();\n    gBS->Stall (3000000);\n  }', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
