p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
bs = chr(92)
code = r'''// IPCC (ADSP/AOP -> AP doorbells) interrupt service: GIC INTID 261.  Nobody registers a handler for it (IPCCDxe does not), so with the ADSP running the level interrupt storms ("Spurious GIC interrupt: 0x105"
// forever = phone hangs).  RamDebugGuard parks it with a quarantine handler that disables the source.  Replace that by a handler that CLEARS the pending signals (RECV_ID -> RECV_SIGNAL_CLEAR) and counts them;
// it disables the source itself if it runs away.
STATIC EFI_HARDWARE_INTERRUPT_PROTOCOL  *mIpccHw;
STATIC volatile UINT32                  mIpccCalls, mIpccSignals;
STATIC volatile UINT32                  mIpccIds[16];

STATIC VOID
EFIAPI
IpccIsr (HARDWARE_INTERRUPT_SOURCE Source, EFI_SYSTEM_CONTEXT Ctx)
{
  UINT32  I, Id;

  mIpccCalls++;
  for (I = 0; I < 64; I++) {
    Id = MMR (IPCC_B + 0x10);
    if (Id == 0xFFFFFFFFU) {
      break;
    }
    MMW (IPCC_B + 0x1C, Id);
    if (mIpccSignals < 16) {
      mIpccIds[mIpccSignals] = Id;
    }
    mIpccSignals++;
  }
  if (mIpccCalls > 20000) {
    mIpccHw->DisableInterruptSource (mIpccHw, Source);
  }
}

STATIC VOID
IpccIsrInstall (VOID)
{
  EFI_STATUS  St1, St2;
  BOOLEAN     IntState;

  if (EFI_ERROR (gBS->LocateProtocol (&gHardwareInterruptProtocolGuid, NULL, (VOID **)&mIpccHw))) {
    PL ("IPCC isr: no hardware interrupt protocol" BSN);
    return;
  }
  IntState = ArmGetInterruptState ();
  ArmDisableInterrupts ();
  St1 = mIpccHw->RegisterInterruptSource (mIpccHw, 261, NULL);       // drop RamDebugGuard's quarantine handler (also disables the source)
  St2 = mIpccHw->RegisterInterruptSource (mIpccHw, 261, IpccIsr);    // enables the source
  if (IntState) {
    ArmEnableInterrupts ();
  }
  PL ("IPCC isr: unregister quarantine -> %r, register own handler -> %r" BSN, St1, St2);
}

STATIC VOID
IpccIsrReport (CONST CHAR8 *Tag)
{
  UINT32  I, N = mIpccSignals < 16 ? mIpccSignals : 16;

  PL ("IPCC isr[%a]: calls=%u signals=%u ids:" BSN, Tag, mIpccCalls, mIpccSignals);
  for (I = 0; I < N; I++) {
    PL ("  id[%u]=0x%08x (client %u signal %u)" BSN, I, mIpccIds[I], mIpccIds[I] >> 16, mIpccIds[I] & 0xFFFF);
  }
}

'''.replace(' BSN', bs + 'n"').replace('"' + bs + 'n"', bs + 'n"')
# the replace above turns `" BSN` pairs into `\n"`; make sure each PL line ends properly
code = code.replace('device' + bs + 'n"', 'device"')
marker = '// ADSP.TXT + NOBOOT:'
assert marker in s and 'IpccIsrInstall' not in s
s = s.replace(marker, code + marker, 1)
# install the ISR before the ADSP load
old = '  T0 = PcNowUs ();\n  R = ((MC_PIL_LOAD)P[1]) (L"FULL_ADSP");'
assert old in s
s = s.replace(old, '  IpccIsrInstall ();\n' + old, 1)
# report after the UCSI probe and after Connect
old2 = '    UcsiCmd (Base, "conn1-status-after", 0x12 | (1ULL << 16));\n  }\n}'
assert old2 in s
s = s.replace(old2, '    UcsiCmd (Base, "conn1-status-after", 0x12 | (1ULL << 16));\n  }\n  IpccIsrReport ("end");\n}', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
