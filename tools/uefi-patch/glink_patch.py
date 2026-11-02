p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
bs = chr(92)
code = r'''// After the ADSP is up: PmicGlinkDxe protocol 7429EB07-F2E3-4A6B-AA96-C909CD956EF7 (only QcomChargerDxe uses it): [0]=revision, then plain functions without This.
// ChargerLibTarget_LinkChargerFW: fn7 = Connect(), fn9 = Connect (ChargerPD logging), fn8 = GetStatus(UINT8 *Connected), polled once a second for 20 s.
STATIC VOID
PmicGlinkLink (VOID)
{
  STATIC EFI_GUID  Guid = { 0x7429EB07, 0xF2E3, 0x4A6B, { 0xAA, 0x96, 0xC9, 0x09, 0xCD, 0x95, 0x6E, 0xF7 } };
  typedef UINTN (EFIAPI *F0) (VOID);
  typedef UINTN (EFIAPI *F1) (UINT8 *);
  UINT64      *P = NULL;
  EFI_STATUS  St;
  UINTN       R;
  UINT8       Up = 0;
  UINT32      I;

  St = gBS->LocateProtocol (&Guid, NULL, (VOID **)&P);
  PL ("LocateProtocol(PmicGlink) -> %r P=%p revision 0x%lx" BSN, St, P, P ? P[0] : 0);
  if (EFI_ERROR (St) || P == NULL) {
    return;
  }
  R = ((F0)P[8]) ();
  PL ("PmicGlink Connect -> 0x%lx" BSN, (UINT64)R);
  R = ((F0)P[10]) ();
  PL ("PmicGlink Connect(logs) -> 0x%lx" BSN, (UINT64)R);
  for (I = 0; I < 20; I++) {
    gBS->Stall (1000000);
    Up = 0xEE;
    R = ((F1)P[9]) (&Up);
    PL ("PmicGlink GetStatus t=%u -> 0x%lx connected=%u" BSN, I, (UINT64)R, Up);
    if (R == 0 && Up == 1) {
      break;
    }
  }
}

'''.replace('BSN', '"' + bs + 'n"').replace('" "' + bs + 'n"', '"' + bs + 'n"')
code = code.replace('" "\n"', '"\n"')
marker = '// ADSP.TXT + NOBOOT:'
assert marker in s and 'PmicGlinkLink' not in s
s = s.replace(marker, code + marker, 1)
old = '  PL ("ProcessPilImage(FULL_ADSP) -> 0x%lx in %lu ms' + bs + 'n", (UINT64)R, (PcNowUs () - T0) / 1000);'
assert old in s
s = s.replace(old, old + '\n  if (R == 0) {\n    PmicGlinkLink ();\n  }', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
