p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
bs = chr(92)
code = r'''// PMIC register read/write through the ADSP (owner 0x800F debug service) on the PMIC_RTR channel (handle image+0xA378).  Reply: glink TX_DATA(cmd 9, hdr 16 B) + hdr(12) bus sid addr len data[]
// (read, opcode 0x37) or hdr(12) status (write, opcode 0x38).  The reply is copied out of the APPS<-ADSP FIFO (item 480) before GlinkDxe's poll consumes it.
STATIC UINT64  mPgBase;

STATIC INTN
PmicDbg (UINT32 Opcode, UINT32 Sid, UINT32 Addr, UINT32 Arg, UINT8 *Data, UINT32 *Len)
{
  UINT64   *GlinkProto = (UINT64 *)(UINTN)(*(UINT64 *)(UINTN)(mPgBase + 0xA370));
  VOID     *Handle = (VOID *)(UINTN)(*(UINT64 *)(UINTN)(mPgBase + 0xA378));
  UINT32   Sz;
  UINT32   *Desc = (UINT32 *)SmemItem (2, 478, &Sz);
  UINT8    *Rx = SmemItem (2, 480, &Sz);
  UINT32   Msg[7], Out = 0, OldHead, I, Pos, Got = 0;
  UINTN    R;
  UINT32   Pay[0x80], Words = 0;

  Msg[0] = 0x800F; Msg[1] = 1; Msg[2] = Opcode; Msg[3] = 0; Msg[4] = Sid; Msg[5] = Addr; Msg[6] = Arg;
  if (Desc == NULL || Rx == NULL) {
    return -1;
  }
  OldHead = Desc[3];
  R = ((MC_GTX)(UINTN)GlinkProto[0x28 / 8]) (Handle, NULL, Msg, sizeof (Msg), 0, &Out);
  if (R != 0) {
    return -2;
  }
  for (I = 0; I < 500; I++) {
    if (Desc[3] != OldHead) {
      break;
    }
    gBS->Stall (1000);
  }
  gBS->Stall (2000);
  // collect words OldHead..Desc[3]
  for (Pos = OldHead; Pos != Desc[3] && Words < 0x80; Pos = (Pos + 4) & 0x3FFF) {
    Pay[Words++] = *(UINT32 *)(Rx + Pos);
  }
  // find TX_DATA (cmd 9) carrying owner 0x800F
  for (I = 0; I + 8 < Words; I++) {
    if ((Pay[I] & 0xFFFF) == 9 && Pay[I + 4] == 0x800F && Pay[I + 6] == Opcode) {
      if (Opcode == 0x37) {
        UINT32  Rl = Pay[I + 9] > 0x100 ? 0x100 : Pay[I + 9];
        if (Data != NULL) {
          CopyMem (Data, &Pay[I + 10], Rl);
        }
        if (Len != NULL) {
          *Len = Pay[I + 9];
        }
        Got = 1;
        break;
      } else {
        if (Len != NULL) {
          *Len = Pay[I + 7];
        }
        Got = 1;
        break;
      }
    }
  }
  // let GlinkDxe process (RX_DONE etc.)
  {
    typedef UINTN (EFIAPI *GPOLL) (VOID *, UINT32 *);
    UINT32  X;
    ((GPOLL)(UINTN)GlinkProto[0x80 / 8]) (Handle, &X);
    gBS->Stall (2000);
    ((GPOLL)(UINTN)GlinkProto[0x80 / 8]) (Handle, &X);
  }
  return Got ? 0 : -3;
}

STATIC VOID
PmicSurvey (VOID)
{
  UINT32  Page;
  UINT8   D[4];
  UINT32  L;

  for (Page = 0; Page < 0x30; Page++) {
    SetMem (D, sizeof (D), 0xEE);
    L = 0;
    if (PmicDbg (0x37, 7, Page * 0x100 + 4, 2, D, &L) == 0 && (D[0] != 0 || D[1] != 0)) {
      PL ("PMIC sid7 page 0x%02x00: type=0x%02x subtype=0x%02x (len %u)" BSN, Page, D[0], D[1], L);
    }
  }
}

'''.replace(' BSN', ' "' + bs + 'n"').replace('" "' + bs + 'n"', bs + 'n"')
marker = '// ADSP.TXT + NOBOOT:'
assert marker in s and 'PmicSurvey' not in s
s = s.replace(marker, code + marker, 1)
s = s.replace('STATIC VOID PmicDbgCall (UINT64 Base,', 'STATIC VOID PmicSurvey (VOID);\nSTATIC UINT64 mPgBase;\nSTATIC VOID PmicDbgCall (UINT64 Base,', 1)
s = s.replace('STATIC UINT64  mPgBase;\n\nSTATIC INTN', 'STATIC INTN', 1)
old = '''  PmicDbgCall (Base, "revid/logs", 0x37, 0, 7, 0x0104, 2, 800, 0xA428);
  PmicDbgCall (Base, "revid/rtr", 0x37, 0, 7, 0x0104, 2, 1500, 0xA378);
  PmicDbgCall (Base, "revid/rtr-2d8", 0x37, 0, 7, 0x0104, 2, 1500, 0xA2D8);
'''
assert old in s
s = s.replace(old, '  mPgBase = Base;\n  PmicSurvey ();\n', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
