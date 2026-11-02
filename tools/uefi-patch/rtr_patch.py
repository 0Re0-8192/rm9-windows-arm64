p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
bs = chr(92)
code = r'''// (1) publish the APPS side of the SMP2P pair (item 429: master-kernel / sleepstate / rdbg) the way Linux does and kick the ADSP (IPCC client 3 / signal 2 = SMP2P)
// (2) open the ADSP's "IPCRTR" glink channel (QRTR = QMI service discovery) with our own callbacks and dump what arrives.
STATIC VOID
Smp2pPublish (VOID)
{
  UINT32  Sz, I;
  UINT32  *P = (UINT32 *)SmemItem (2, 429, &Sz);
  STATIC CONST CHAR8  *Names[3] = { "master-kernel", "sleepstate", "rdbg" };
  STATIC CONST UINT32  Vals[3]  = { 0, 0x1000, 0 };

  if (P == NULL) {
    PL ("SMP2P publish: item 429 missing" BSN);
    return;
  }
  for (I = 0; I < 3; I++) {
    UINT8   *Ent = (UINT8 *)(P + 5 + 5 * I);
    UINT32  K;
    SetMem (Ent, 16, 0);
    for (K = 0; Names[I][K] != 0; K++) {
      Ent[K] = (UINT8)Names[I][K];
    }
    *(volatile UINT32 *)(Ent + 16) = Vals[I];
  }
  P[3] = (3U << 16) | 0x10;           // valid_entries = 3, total_entries = 16
  MemoryFence ();
  MMW (IPCC_B + 0x0C, (3U << 16) | 2); // kick LPASS / SMP2P
  PL ("SMP2P publish: item 429 now valid_entries=%u, kicked ADSP" BSN, P[3] >> 16);
}

STATIC UINT32  mRtrCount;
STATIC UINT32  mRtrState = 0xFF;
STATIC UINT32  mRtrLen[8];
STATIC UINT8   mRtrBuf[8][128];
STATIC UINT64  mRtrProto;

STATIC VOID
EFIAPI
RtrRx (VOID *H, VOID *Priv, VOID *PktPriv, CONST VOID *Ptr, UINTN Size, UINTN Used)
{
  typedef UINTN (EFIAPI *RXDONE) (VOID *, CONST VOID *, UINT8, UINT32 *);
  UINT32  St = 0;

  if (mRtrCount < 8) {
    UINTN  N = Size > 128 ? 128 : Size;
    CopyMem (mRtrBuf[mRtrCount], Ptr, N);
    mRtrLen[mRtrCount] = (UINT32)Size;
  }
  mRtrCount++;
  ((RXDONE)(UINTN)((UINT64 *)(UINTN)mRtrProto)[0x40 / 8]) (H, Ptr, 1, &St);
}

STATIC VOID
EFIAPI
RtrState (VOID *H, VOID *Priv, UINT32 State)
{
  typedef UINTN (EFIAPI *QINT) (VOID *, VOID *, UINTN, UINT32 *);
  UINT32  I, St = 0;

  mRtrState = State;
  if (State == 0) {
    for (I = 0; I < 6; I++) {
      ((QINT)(UINTN)((UINT64 *)(UINTN)mRtrProto)[0x38 / 8]) (H, NULL, 0x1000, &St);
    }
  }
}

STATIC VOID
EFIAPI
RtrTxDone (VOID *A, VOID *B, VOID *C, VOID *D, VOID *E)
{
}

STATIC VOID
RtrOpen (UINT64 Base)
{
  typedef UINTN (EFIAPI *GOPEN) (VOID *, VOID **, UINT32 *);
  UINT64  *Proto = (UINT64 *)(UINTN)(*(UINT64 *)(UINTN)(Base + 0xA220));
  UINT8   Cfg[0x90];
  VOID    *Handle = NULL;
  UINT32  St = 0xFFFFFFF5, I;
  UINTN   R;
  UINT32  X;
  STATIC CONST CHAR8  Name[] = "IPCRTR";

  mRtrProto = (UINT64)(UINTN)Proto;
  CopyMem (Cfg, (VOID *)(UINTN)(Base + 0xA2E0), sizeof (Cfg));
  *(UINT64 *)(Cfg + 0x00) = (UINT64)(UINTN)Name;
  *(UINT64 *)(Cfg + 0x28) = (UINT64)(UINTN)RtrRx;
  *(UINT64 *)(Cfg + 0x40) = (UINT64)(UINTN)RtrTxDone;
  *(UINT64 *)(Cfg + 0x48) = (UINT64)(UINTN)RtrState;
  R = ((GOPEN)(UINTN)Proto[0x18 / 8]) (Cfg, &Handle, &St);
  PL ("IPCRTR open -> 0x%lx status=%d handle=%p" BSN, (UINT64)R, (INT32)St, Handle);
  for (I = 0; I < 3000 && Handle != NULL; I++) {
    typedef UINTN (EFIAPI *GPOLL) (VOID *, UINT32 *);
    ((GPOLL)(UINTN)Proto[0x80 / 8]) (Handle, &X);
    gBS->Stall (1000);
    if (mRtrCount >= 8) {
      break;
    }
  }
  PL ("IPCRTR: state=%d rx messages=%u" BSN, (INT32)mRtrState, mRtrCount);
  for (I = 0; I < mRtrCount && I < 8; I++) {
    UINT32  *W = (UINT32 *)mRtrBuf[I];
    PL ("  rtr[%u] len=%u: %08x %08x %08x %08x %08x %08x %08x %08x" BSN, I, mRtrLen[I], W[0], W[1], W[2], W[3], W[4], W[5], W[6], W[7]);
  }
}

'''.replace(' BSN', ' "' + bs + 'n"').replace('" "' + bs + 'n"', bs + 'n"')
marker = '// ADSP.TXT + NOBOOT:'
assert marker in s and 'RtrOpen' not in s
s = s.replace(marker, code + marker, 1)
s = s.replace('STATIC VOID Smp2pDump (CONST CHAR8 *Tag);\n', 'STATIC VOID Smp2pDump (CONST CHAR8 *Tag);\nSTATIC VOID Smp2pPublish (VOID);\nSTATIC VOID RtrOpen (UINT64 Base);\n', 1)
old = '  if (mIpccTimer != NULL) {\n    gBS->SetTimer (mIpccTimer, TimerCancel, 0);'
assert old in s
s = s.replace(old, '  if (SelfFileExists (L"' + bs * 2 + 'RTR.TXT")) {\n    Smp2pPublish ();\n    gBS->Stall (1000000);\n    Smp2pDump ("after-publish");\n    RtrOpen (Base);\n  }\n' + old, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
