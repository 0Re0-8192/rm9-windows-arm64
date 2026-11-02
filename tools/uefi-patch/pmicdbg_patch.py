p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
bs = chr(92)
code = r'''// PMIC register access through the ADSP (pmic_glink_debug protocol, reverse engineered from pmic-glink-debug.ko): owner 0x800F, type 1;
//   read : opcode 0x37, {bus, sid, addr, len}  -> response opcode 0x37, 0x11C bytes: hdr(12) bus sid addr len(status) data[0x100]
//   write: opcode 0x38, {bus, sid, addr, data} -> response opcode 0x38, 0x10 bytes: hdr(12) status
// Sent with the glink-tx of PmicGlinkDxe's second channel (PMIC_LOGS_ADSP_APPS, handle at image+0xA428); the reply is read straight out of the APPS<-ADSP FIFO (item 480) without consuming it.
typedef UINTN (EFIAPI *MC_GTX) (VOID *Handle, VOID *Priv, VOID *Data, UINTN Size, UINT32 Flags, UINT32 *Out);

STATIC VOID
PmicDbgCall (UINT64 Base, CONST CHAR8 *Tag, UINT32 Opcode, UINT32 A, UINT32 B, UINT32 C, UINT32 D, UINT32 RxWaitMs)
{
  UINT64   *GlinkProto = (UINT64 *)(UINTN)(*(UINT64 *)(UINTN)(Base + 0xA370));
  VOID     *Handle = (VOID *)(UINTN)(*(UINT64 *)(UINTN)(Base + 0xA428));
  UINT32   Sz;
  UINT32   *Desc = (UINT32 *)SmemItem (2, 478, &Sz);
  UINT8    *Rx = SmemItem (2, 480, &Sz);
  UINT32   Msg[7], Out = 0, OldHead, I;
  UINTN    R;

  Msg[0] = 0x800F; Msg[1] = 1; Msg[2] = Opcode; Msg[3] = A; Msg[4] = B; Msg[5] = C; Msg[6] = D;
  if (Desc == NULL || Rx == NULL || Handle == NULL || GlinkProto == NULL) {
    PL ("PMICDBG %a: missing desc/rx/handle (%p %p %p %p)" BSN, Tag, Desc, Rx, Handle, GlinkProto);
    return;
  }
  OldHead = Desc[3];
  R = ((MC_GTX)(UINTN)GlinkProto[0x28 / 8]) (Handle, NULL, Msg, sizeof (Msg), 0, &Out);
  PL ("PMICDBG %a: tx op=0x%x bus=%u sid=%u addr=0x%x x=%u -> 0x%lx out=%u (rx tail=%x head=%x)" BSN, Tag, Opcode, A, B, C, D, (UINT64)R, Out, Desc[2], Desc[3]);
  for (I = 0; I < RxWaitMs; I++) {
    if (Desc[3] != OldHead) {
      break;
    }
    gBS->Stall (1000);
  }
  gBS->Stall (20000);
  PL ("PMICDBG %a: after %u ms rx tail=%x head=%x (old head %x)" BSN, Tag, I, Desc[2], Desc[3], OldHead);
  for (I = OldHead & ~0x1FU; I < Desc[3] + 0x20 && I < OldHead + 0x180; I += 32) {
    UINT32  *W = (UINT32 *)(Rx + (I % 0x4000));
    PL ("   rx %04x: %08x %08x %08x %08x %08x %08x %08x %08x" BSN, I, W[0], W[1], W[2], W[3], W[4], W[5], W[6], W[7]);
  }
}

'''.replace(' BSN', ' "' + bs + 'n"').replace('" "' + bs + 'n"', bs + 'n"')
marker = '// ADSP.TXT + NOBOOT:'
assert marker in s and 'PmicDbgCall' not in s
s = s.replace(marker, code + marker, 1)
# call it from UcsiProbe start (after the service wait), reading two registers
old = '  UcsiCmd (Base, "read", 0);'
assert old in s
call = '''  if (mIpccTimer != NULL) {
    gBS->SetTimer (mIpccTimer, TimerCancel, 0);   // keep GlinkDxe from consuming the ADSP reply
  }
  PmicDbgCall (Base, "revid", 0x37, 0, 7, 0x0104, 2, 1500);
  PmicDbgCall (Base, "typec-type", 0x37, 0, 7, 0x1504, 2, 1500);
  PmicDbgCall (Base, "typec-state", 0x37, 0, 7, 0x1509, 4, 1500);
'''
s = s.replace(old, call + old, 1)
# timer handle
s = s.replace('STATIC UINT64   mIpccCfg;', 'STATIC UINT64   mIpccCfg;\nSTATIC EFI_EVENT mIpccTimer;', 1)
s = s.replace('  St = gBS->CreateEvent (EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, IpccPollCb, NULL, &Ev);', '  St = gBS->CreateEvent (EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, IpccPollCb, NULL, &Ev);\n  mIpccTimer = Ev;', 1)
s = s.replace('STATIC UINT8 *SmemItem (UINT16 Host1, UINT16 Item, UINT32 *OutSize);\n', 'STATIC UINT8 *SmemItem (UINT16 Host1, UINT16 Item, UINT32 *OutSize);\nSTATIC EFI_EVENT mIpccTimer;\n', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
