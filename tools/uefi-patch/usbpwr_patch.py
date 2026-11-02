import sys
p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
BS = chr(92)
code = r'''// USBPWR.TXT + NOBOOT: Qualcomm's UsbPwrCtrlDxe protocol (reverse engineered, see HANDOVER 0.16): Revision 0x10003 followed by 12 plain functions with NO This pointer:
//   1 GetVbusDetect(port,out) 2 GetVbusSourceOK 3 GetHSUsbChgPortType 4 GetUsbIDStatus 5 GetTypeCPortStatus 6 GetPDStatus(port,out[0x18]) 7 SetSnkMaxInputCurrent(port,mA)
//   8 SetSrcMaxOutputCurrent(port,mA) 9 SetVbusEn(port,en) 10 SetVconnEn(port,en) 11 ? 12 stub.  Read-only unless USBPWR1.TXT exists (then SetVbusEn(0,1) for 3 s).
typedef UINTN (EFIAPI *MC_PWR_FN) (UINTN Port, VOID *Out, VOID *Out2);

STATIC VOID
UsbPwrGetters (CONST CHAR8 *Tag, UINT64 *Fn)
{
  STATIC CONST CHAR8  *Names[] = { "GetVbusDetect", "GetVbusSourceOK", "GetHSUsbChgPortType", "GetUsbIDStatus", "GetTypeCPortStatus", "GetPDStatus" };
  UINT32  Port, I, K;
  UINT32  Buf[16], Buf2[16];
  UINTN   St;

  for (Port = 0; Port < 2; Port++) {
    for (I = 0; I < 6; I++) {
      for (K = 0; K < 16; K++) {
        Buf[K] = 0xA5A5A5A5;
        Buf2[K] = 0xA5A5A5A5;
      }
      St = ((MC_PWR_FN)Fn[I]) (Port, Buf, Buf2);
      PL ("PWR[%a] port%u %a -> 0x%lx out: %08x %08x %08x %08x %08x %08x | %08x %08x\n", Tag, Port, Names[I], (UINT64)St, Buf[0], Buf[1], Buf[2], Buf[3], Buf[4], Buf[5], Buf2[0], Buf2[1]);
    }
  }
}

STATIC VOID
UsbPwrProbe (VOID)
{
  STATIC EFI_GUID  Guid = { 0xE07DF17E, 0xE79E, 0x4150, { 0x93, 0x78, 0x50, 0x62, 0x3A, 0x14, 0x99, 0x4A } };
  UINT64      *P = NULL;
  EFI_STATUS  St;
  UINT32      I;

  PL ("=== UsbPwrCtrl probe\n");
  St = gBS->LocateProtocol (&Guid, NULL, (VOID **)&P);
  PL ("LocateProtocol(UsbPwrCtrl) -> %r P=%p\n", St, P);
  if (EFI_ERROR (St) || P == NULL) {
    return;
  }
  PL ("revision 0x%lx fns:", P[0]);
  for (I = 1; I <= 12; I++) {
    PL (" %p", (VOID *)P[I]);
  }
  PL ("\n");
  UsbPwrGetters ("before", &P[1]);
  if (SelfFileExists (L"BSBSUSBPWR1.TXT")) {
    St = ((MC_PWR_FN)P[9]) (0, (VOID *)1, NULL);
    PL ("SetVbusEn(0,1) -> 0x%lx\n", (UINT64)St);
    gBS->Stall (3000000);
    UsbPwrGetters ("vbus-on", &P[1]);
    St = ((MC_PWR_FN)P[9]) (0, NULL, NULL);
    PL ("SetVbusEn(0,0) -> 0x%lx\n", (UINT64)St);
    UsbPwrGetters ("vbus-off", &P[1]);
  }
}

'''.replace('BSBS', BS * 2)
marker = 'STATIC VOID\nDumpMemMap (VOID)'
assert marker in s
s = s.replace(marker, code + marker, 1)
old = '  if (mNoBoot && SelfFileExists (L"' + BS * 2 + 'USBDEV.TXT")) {'
assert old in s
new = ('  if (mNoBoot && SelfFileExists (L"' + BS * 2 + 'USBPWR.TXT")) {\n    UsbPwrProbe ();\n'
       '    DEBUG ((DEBUG_ERROR, "[MUCHAIN] USBPWR.TXT: usb power probe done' + BS + 'n"));\n    CpuDeadLoop ();\n    return EFI_SUCCESS;\n  }\n') + old
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
