p='<RM9_WORKDIR>/refs/MuChain.c'
s=open(p,encoding='utf-8',newline='').read()
BS=chr(92)
# 1. snapshot buffer in poll callback
old='''  mIpccPollBusy = TRUE;
  mIpccPollCalls++;
  ((ISR_FN)(UINTN)(mIpccDxeBase + 0x2A9C)) ((VOID *)(UINTN)mIpccCfg);'''
assert old in s
new='''  mIpccPollBusy = TRUE;
  mIpccPollCalls++;
  if (mRxSnapOn) {   // copy new APPS<-ADSP FIFO bytes before GlinkDxe consumes (zeroes) them
    UINT32  Sz0;
    if (mRxDesc == NULL) {
      mRxDesc = (UINT32 *)SmemItem (2, 478, &Sz0);
      mRxFifo = SmemItem (2, 480, &Sz0);
      mRxLast = mRxDesc != NULL ? mRxDesc[3] : 0;
    }
    if (mRxDesc != NULL && mRxFifo != NULL) {
      UINT32  Hd = mRxDesc[3];
      while (mRxLast != Hd && mRxLogLen < sizeof (mRxLog)) {
        mRxLog[mRxLogLen++] = mRxFifo[mRxLast % 0x4000];
        mRxLast = (mRxLast + 1) % 0x4000;
      }
    }
  }
  ((ISR_FN)(UINTN)(mIpccDxeBase + 0x2A9C)) ((VOID *)(UINTN)mIpccCfg);'''
s=s.replace(old,new,1)
decl='''STATIC BOOLEAN  mIpccPollBusy;'''
assert decl in s
s=s.replace(decl,decl+'''
STATIC BOOLEAN  mRxSnapOn;
STATIC UINT32   *mRxDesc;
STATIC UINT8    *mRxFifo;
STATIC UINT32   mRxLast, mRxLogLen;
STATIC UINT8    mRxLog[0x40000];''',1)
# 2. don't cancel timer when PMICRAW.TXT (we want it to run)
old2='''  if (mIpccTimer != NULL) {
    gBS->SetTimer (mIpccTimer, TimerCancel, 0);   // keep GlinkDxe from consuming the ADSP reply
  }'''
assert old2 in s
s=s.replace(old2,'''  if (mIpccTimer != NULL && !SelfFileExists (L"''' + BS*2 + '''PMICRAW.TXT")) {
    gBS->SetTimer (mIpccTimer, TimerCancel, 0);   // keep GlinkDxe from consuming the ADSP reply
  }''',1)
# 3. PmicDbgCall: snapshot mode
i=s.index('PmicDbgCall (UINT64 Base, CONST CHAR8 *Tag')
j=s.index('\n}\n',i)
func=s[i:j+3]
newfunc='''PmicDbgCall (UINT64 Base, CONST CHAR8 *Tag, UINT32 Opcode, UINT32 A, UINT32 B, UINT32 C, UINT32 D, UINT32 RxWaitMs, UINT32 HandleOff)
{
  UINT64   *GlinkProto = (UINT64 *)(UINTN)(*(UINT64 *)(UINTN)(Base + 0xA370));
  VOID     *Handle = (VOID *)(UINTN)(*(UINT64 *)(UINTN)(Base + HandleOff));
  UINT32   Msg[8], Out = 0, Start, I, Idle;
  UINTN    R;

  Msg[7] = 0;
  Msg[0] = mDbgOwner; Msg[1] = 1; Msg[2] = Opcode; Msg[3] = A; Msg[4] = B; Msg[5] = C; Msg[6] = D;
  if (Handle == NULL || GlinkProto == NULL || mIpccTimer == NULL) {
    PL ("PMICDBG %a: missing handle/proto/timer (%p %p %p)''' + BS + '''n", Tag, Handle, GlinkProto, mIpccTimer);
    return;
  }
  if (!mRxSnapOn) {
    mRxSnapOn = TRUE;
    gBS->SetTimer (mIpccTimer, TimerPeriodic, 20000);   // 2 ms poll: GlinkDxe keeps running, the callback snapshots the FIFO first
    gBS->Stall (300000);
  }
  Start = mRxLogLen;
  R = ((MC_GTX)(UINTN)GlinkProto[0x28 / 8]) (Handle, NULL, Msg, Opcode == 0x19 ? 32 : 28, 0, &Out);
  PL ("PMICDBG %a: tx op=0x%x A=%x B=%x C=%x D=%x -> 0x%lx out=%d''' + BS + '''n", Tag, Opcode, A, B, C, D, (UINT64)R, (INT32)Out);
  Idle = 0;
  for (I = 0; I < RxWaitMs && Idle < 300; I++) {   // done once the stream has been quiet for 300 ms
    UINT32  Before = mRxLogLen;
    gBS->Stall (1000);
    Idle = (mRxLogLen != Before || mRxLogLen == Start) ? 0 : Idle + 1;
  }
  PL ("PMICDBG %a: captured %u bytes''' + BS + '''n", Tag, mRxLogLen - Start);
  for (I = Start & ~0x1FU; I < mRxLogLen && I < Start + 0x6000; I += 32) {
    UINT32  *W = (UINT32 *)(mRxLog + I);
    PL ("   rx %04x: %08x %08x %08x %08x %08x %08x %08x %08x''' + BS + '''n", I, W[0], W[1], W[2], W[3], W[4], W[5], W[6], W[7]);
  }
}
'''
s=s[:i]+newfunc+s[j+3:]
open(p,'w',encoding='utf-8',newline='').write(s)
print('ok')
