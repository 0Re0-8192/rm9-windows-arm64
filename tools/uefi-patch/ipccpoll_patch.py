p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
bs = chr(92)
code = r'''// Poll IPCCDxe's own interrupt routine (image+0x2A9C(cfg)) from a periodic timer instead of the IRQ (nobody could register it: quarantine / DAL IST): it dispatches the ADSP's SMP2P / glink doorbells
// to Smp2pDxe / GlinkDxe.
STATIC UINT64   mIpccCfg;
STATIC UINT64   mIpccDxeBase = 0xD213D000ULL;
STATIC BOOLEAN  mIpccPollBusy;
STATIC UINT32   mIpccPollCalls;

STATIC UINT64
IpccFindCfg (VOID)
{
  UINT64  P, Best = 0;

  for (P = 0xCF000000ULL; P < 0xD2A00000ULL; P += 8) {
    UINT64  V = *(UINT64 *)(UINTN)(P + 0x10);
    UINT16  Id = *(UINT16 *)(UINTN)(P + 6);
    if (V == 0x406000ULL && Id == 261) {
      UINT64  Tbl = *(UINT64 *)(UINTN)(P + 0x18);
      if (Tbl > 0x80000000ULL && Tbl < 0x100000000ULL) {
        UINT64  *T = (UINT64 *)(UINTN)(Tbl + 16 * 3);
        PL ("IPCC cfg @%lx tbl=%lx client3 head=%lx" BSN, P, Tbl, T[0]);
        if (T[0] != 0 || Best == 0) {
          Best = P;
        }
      }
    }
  }
  return Best;
}

STATIC VOID
EFIAPI
IpccPollCb (IN EFI_EVENT Ev, IN VOID *Ctx)
{
  typedef VOID (EFIAPI *ISR_FN) (VOID *);

  if (mIpccPollBusy || mIpccCfg == 0) {
    return;
  }
  mIpccPollBusy = TRUE;
  mIpccPollCalls++;
  ((ISR_FN)(UINTN)(mIpccDxeBase + 0x2A9C)) ((VOID *)(UINTN)mIpccCfg);
  mIpccPollBusy = FALSE;
}

STATIC VOID
IpccPollStart (VOID)
{
  EFI_EVENT   Ev;
  EFI_STATUS  St;

  if (*(UINT16 *)(UINTN)mIpccDxeBase != 0x5A4D) {
    PL ("IPCC poll: IPCCDxe not at 0x%lx" BSN, mIpccDxeBase);
    return;
  }
  mIpccCfg = IpccFindCfg ();
  PL ("IPCC poll: using cfg %lx" BSN, mIpccCfg);
  if (mIpccCfg == 0) {
    return;
  }
  St = gBS->CreateEvent (EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, IpccPollCb, NULL, &Ev);
  if (!EFI_ERROR (St)) {
    St = gBS->SetTimer (Ev, TimerPeriodic, 100000);
  }
  PL ("IPCC poll: timer -> %r" BSN, St);
}

'''.replace(' BSN', bs and ' "' + bs + 'n"').replace('" "' + bs + 'n"', bs + 'n"')
code = code.replace('"\n"', '\n"')
marker = '// ADSP.TXT + NOBOOT:'
assert marker in s and 'IpccPollStart' not in s
s = s.replace(marker, code + marker, 1)
# use the poller instead of the own ISR
assert '  IpccIsrInstall ();\n' in s
s = s.replace('  IpccIsrInstall ();\n', '', 1)
old = '  if (R == 0) {\n    gBS->Stall (8000000);'
assert old in s
s = s.replace(old, '  if (R == 0) {\n    IpccPollStart ();\n    gBS->Stall (8000000);', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
