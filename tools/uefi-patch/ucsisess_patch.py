p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
BS = chr(92)
NL = BS + 'n'
code = r'''// ---- mini glink-native for channel 8 (PMIC_RTR_ADSP_APPS), used after GlinkDxe's poll is stopped.  FIFO layout: SMEM item 479 = AP->ADSP, 480 = ADSP->AP, item 478 = descriptor
//   (tx tail, tx head, rx tail, rx head).  Messages are 8-byte aligned: TX_DATA = 16-byte header {cmd|ch<<16, riid, size, left} + payload; RX_DONE_W_REUSE = {0xE|ch<<16, riid}.
//   The ADSP's receive intents for this channel (ids 0..5, 512 B) are tracked in mMgFree and given back by the ADSP's own RX_DONE messages.
STATIC UINT32  *mMgD;
STATIC UINT8   *mMgTx, *mMgRx;
STATIC UINT32  mMgPos, mMgFree, mMgMsgLen, mMgMsgSeq, mMgAsmLen;
STATIC UINT8   mMgMsg[1024], mMgAsm[1024];

STATIC BOOLEAN
MgInit (VOID)
{
  UINT32  Sz;

  mMgD  = (UINT32 *)SmemItem (2, 478, &Sz);
  mMgTx = SmemItem (2, 479, &Sz);
  mMgRx = SmemItem (2, 480, &Sz);
  if (mMgD == NULL || mMgTx == NULL || mMgRx == NULL) {
    return FALSE;
  }
  mMgPos = mMgD[3];
  mMgFree = 0x3F;
  mMgMsgLen = 0;
  mMgMsgSeq = 0;
  mMgAsmLen = 0;
  return TRUE;
}

STATIC VOID
MgTxWords (CONST UINT32 *W, UINT32 N)
{
  UINT32  Head = mMgD[1], I;

  for (I = 0; I < N; I++) {
    *(volatile UINT32 *)(mMgTx + Head) = W[I];
    Head = (Head + 4) & 0x3FFF;
  }
  MemoryFence ();
  mMgD[1] = Head;
  MemoryFence ();
  MMW (IPCC_B + 0x0C, 0x30000);   // IPCC SEND_ID: client 3 (ADSP), signal 0 (glink)
}

STATIC VOID
MgPoll (VOID)
{
  UINT32  Head = mMgD[3];
  UINT32  Avail;

  while (mMgPos != Head) {
    Avail = (Head - mMgPos) & 0x3FFF;
    if (Avail < 8) {
      break;
    }
    {
      UINT32  W0 = *(volatile UINT32 *)(mMgRx + mMgPos);
      UINT32  W1 = *(volatile UINT32 *)(mMgRx + ((mMgPos + 4) & 0x3FFF));
      UINT32  Cmd = W0 & 0xFFFF, Ch = W0 >> 16, Adv = 8;

      if (Cmd == 9 || Cmd == 12 || Cmd == 13) {         // TX_DATA(+CONT)
        UINT32  Size, Left, I;
        if (Avail < 16) {
          break;
        }
        Size = *(volatile UINT32 *)(mMgRx + ((mMgPos + 8) & 0x3FFF));
        Left = *(volatile UINT32 *)(mMgRx + ((mMgPos + 12) & 0x3FFF));
        Adv = 16 + ((Size + 7) & ~7U);
        if (Avail < Adv) {
          break;
        }
        if (Ch == 8) {
          for (I = 0; I < Size && mMgAsmLen < sizeof (mMgAsm); I++) {
            mMgAsm[mMgAsmLen++] = mMgRx[(mMgPos + 16 + I) & 0x3FFF];
          }
          if (Left == 0) {
            UINT32  Rd[2];
            CopyMem (mMgMsg, mMgAsm, mMgAsmLen);
            mMgMsgLen = mMgAsmLen;
            mMgAsmLen = 0;
            mMgMsgSeq++;
            Rd[0] = 0x0000000E | (8 << 16);   // RX_DONE_W_REUSE: hand the intent back
            Rd[1] = W1;
            MgTxWords (Rd, 2);
          }
        }
      } else if (Cmd == 5) {                             // INTENT: header + n * {size,id}
        Adv = 8 + 8 * W1;
        if (Avail < Adv) {
          break;
        }
      } else if (Cmd == 2) {                             // OPEN: header + name
        Adv = 8 + (((W1 & 0xFFFF) + 7) & ~7U);
        if (Avail < Adv) {
          break;
        }
      } else if ((Cmd == 14 || Cmd == 6) && Ch == 8 && W1 < 6) {   // ADSP released one of its intents
        mMgFree |= 1U << W1;
      }
      mMgPos = (mMgPos + Adv) & 0x3FFF;
    }
  }
  mMgD[2] = mMgPos;   // free the ring for the ADSP
}

STATIC BOOLEAN
MgSend (CONST VOID *Msg, UINT32 Size)
{
  UINT32  Words[300], I, T, Ri = 0xFF;
  UINT32  Padded = (Size + 7) & ~7U;

  for (T = 0; T < 1000 && Ri == 0xFF; T++) {
    MgPoll ();
    for (I = 0; I < 6; I++) {
      if ((mMgFree & (1U << I)) != 0) {
        Ri = I;
        break;
      }
    }
    if (Ri == 0xFF) {
      gBS->Stall (1000);
    }
  }
  if (Ri == 0xFF || Padded > sizeof (Words) - 16) {
    return FALSE;
  }
  mMgFree &= ~(1U << Ri);
  SetMem (Words, sizeof (Words), 0);
  Words[0] = 0x00000009 | (8 << 16);
  Words[1] = Ri;
  Words[2] = Size;
  Words[3] = 0;
  CopyMem (Words + 4, Msg, Size);
  MgTxWords (Words, 4 + Padded / 4);
  return TRUE;
}

// wait for a reply with the given owner/opcode; the message ends up in mMgMsg
STATIC BOOLEAN
MgWait (UINT32 Owner, UINT32 Opcode, UINT32 TimeoutMs)
{
  UINT32  T, Seen = mMgMsgSeq;

  for (T = 0; T < TimeoutMs; T++) {
    MgPoll ();
    if (mMgMsgSeq != Seen) {
      UINT32  *W = (UINT32 *)mMgMsg;
      Seen = mMgMsgSeq;
      if (W[0] == Owner && W[2] == Opcode) {
        return TRUE;
      }
    }
    gBS->Stall (1000);
  }
  return FALSE;
}

// UCSI buffer (48 B) in the reply: ver(2) rsv(2) CCI(4) CONTROL(8) MESSAGE_IN(16) MESSAGE_OUT(16)
STATIC BOOLEAN
RtrUcsiRead (UINT8 *Buf48)
{
  UINT32  Rq[3];

  Rq[0] = 0x800B; Rq[1] = 1; Rq[2] = 0x11;
  if (!MgSend (Rq, 12) || !MgWait (0x800B, 0x11, 1000) || mMgMsgLen < 12 + 48) {
    return FALSE;
  }
  CopyMem (Buf48, mMgMsg + 12, 48);
  return TRUE;
}

STATIC VOID
RtrUcsiShow (CONST CHAR8 *Tag, CONST UINT8 *B)
{
  PL ("UCSI.RTR[%a] ver=%04x cci=%08x ctrl=%016lx in=%08x %08x %08x %08x out=%08x %08x %08x %08x@@NL@@", Tag, *(CONST UINT16 *)B, *(CONST UINT32 *)(B + 4), *(CONST UINT64 *)(B + 8),
      *(CONST UINT32 *)(B + 16), *(CONST UINT32 *)(B + 20), *(CONST UINT32 *)(B + 24), *(CONST UINT32 *)(B + 28), *(CONST UINT32 *)(B + 32), *(CONST UINT32 *)(B + 36), *(CONST UINT32 *)(B + 40), *(CONST UINT32 *)(B + 44));
}

// write CONTROL, then poll CCI until a completion bit shows, acknowledge, return the buffer after completion
STATIC UINT32
RtrUcsiCmd (CONST CHAR8 *Tag, UINT64 Control, UINT8 *Out48)
{
  UINT32  Rq[16];
  UINT8   B[48];
  UINT32  T, Cci = 0;

  ZeroMem (Rq, sizeof (Rq));
  ZeroMem (B, sizeof (B));
  Rq[0] = 0x800B; Rq[1] = 1; Rq[2] = 0x12;
  CopyMem ((UINT8 *)Rq + 12 + 8, &Control, 8);
  if (!MgSend (Rq, 64)) {
    PL ("UCSI.RTR %a: send failed@@NL@@", Tag);
    return 0xFFFFFFFF;
  }
  MgWait (0x800B, 0x12, 500);
  for (T = 0; T < 30; T++) {
    gBS->Stall (100000);
    if (!RtrUcsiRead (B)) {
      continue;
    }
    Cci = *(UINT32 *)(B + 4);
    if ((Cci & 0xC8000000U) != 0) {   // command complete / error / reset complete
      break;
    }
  }
  RtrUcsiShow (Tag, B);
  if (Out48 != NULL) {
    CopyMem (Out48, B, 48);
  }
  if ((Cci & 0x80000000U) != 0) {   // acknowledge command completion
    UINT32  A[16];
    UINT64  Ack = 0x04 | (1ULL << 17);
    ZeroMem (A, sizeof (A));
    A[0] = 0x800B; A[1] = 1; A[2] = 0x12;
    CopyMem ((UINT8 *)A + 12 + 8, &Ack, 8);
    MgSend (A, 64);
    MgWait (0x800B, 0x12, 300);
    gBS->Stall (200000);
    RtrUcsiRead (B);
  }
  return Cci;
}

STATIC VOID
RtrUcsiSession (VOID)
{
  UINT8   B[48];
  UINT32  Pan[4];

  if (mIpccTimer != NULL) {
    gBS->SetTimer (mIpccTimer, TimerCancel, 0);   // from now on this code is the only glink user
  }
  gBS->Stall (200000);
  if (!MgInit ()) {
    PL ("UCSI.RTR: mini glink init failed@@NL@@");
    return;
  }
  Pan[0] = 0x800C; Pan[1] = 1; Pan[2] = 0x15; Pan[3] = 1;   // altmode PAN_EN, like the Linux driver
  MgSend (Pan, 16);
  gBS->Stall (200000);
  if (RtrUcsiRead (B)) {
    RtrUcsiShow ("read", B);
  } else {
    PL ("UCSI.RTR: first read failed@@NL@@");
    return;
  }
  RtrUcsiCmd ("ppm-reset", 0x01, B);
  RtrUcsiCmd ("notif-en", 0x05 | (0x8001ULL << 16), B);
  RtrUcsiCmd ("get-cap", 0x06, B);
  RtrUcsiCmd ("conn1-status", 0x12 | (1ULL << 16), B);
  RtrUcsiCmd ("conn2-status", 0x12 | (2ULL << 16), B);
}

'''.replace('@@NL@@', NL)

marker = 'STATIC VOID\nUcsiCmd (UINT64 Base, CONST CHAR8 *Tag, UINT64 Command)'
assert marker in s
s = s.replace(marker, code + marker, 1)

# call at the start of the PMICRAW block in UcsiProbe: find the block that begins with the first PmicDbgCall tests
a = '  if (SelfFileExists (L"' + BS * 2 + 'PMICRAW.TXT")) {\n'
i = s.index(a)
s = s[:i + len(a)] + '    RtrUcsiSession ();\n    return;\n' + s[i + len(a):]
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
