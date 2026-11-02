p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
BS = chr(92)
NL = BS + 'n'

# 1. second channel (9 = PMIC_LOGS) in the mini glink
old = 'STATIC UINT8   mMgMsg[1024], mMgAsm[1024];'
assert old in s
s = s.replace(old, old + '''
STATIC UINT32  mMgFree9, mMgMsgLen9, mMgMsgSeq9, mMgAsmLen9;      // channel 9: ADSP intents are ids 6..11 (bit = id-6)
STATIC UINT8   mMgMsg9[9000], mMgAsm9[9000];''', 1)

old = '  mMgAsmLen = 0;\n  return TRUE;\n}'
assert old in s
s = s.replace(old, '  mMgAsmLen = 0;\n  mMgFree9 = 0x3F;\n  mMgMsgLen9 = 0;\n  mMgMsgSeq9 = 0;\n  mMgAsmLen9 = 0;\n  return TRUE;\n}', 1)

# TX_DATA branch: add channel 9
old = '''        if (Ch == 8) {
          for (I = 0; I < Size && mMgAsmLen < sizeof (mMgAsm); I++) {'''
assert old in s
new = '''        if (Ch == 9) {
          for (I = 0; I < Size && mMgAsmLen9 < sizeof (mMgAsm9); I++) {
            mMgAsm9[mMgAsmLen9++] = mMgRx[(mMgPos + 16 + I) & 0x3FFF];
          }
          if (Left == 0) {
            UINT32  Rd9[2];
            CopyMem (mMgMsg9, mMgAsm9, mMgAsmLen9);
            mMgMsgLen9 = mMgAsmLen9;
            mMgAsmLen9 = 0;
            mMgMsgSeq9++;
            Rd9[0] = 0x0000000E | (9 << 16);
            Rd9[1] = W1;
            MgTxWords (Rd9, 2);
          }
        }
        if (Ch == 8) {
          for (I = 0; I < Size && mMgAsmLen < sizeof (mMgAsm); I++) {'''
s = s.replace(old, new, 1)

old = '''      } else if ((Cmd == 14 || Cmd == 6) && Ch == 8 && W1 < 6) {   // ADSP released one of its intents
        mMgFree |= 1U << W1;
      }'''
assert old in s
new = '''      } else if ((Cmd == 14 || Cmd == 6) && Ch == 8 && W1 < 6) {   // ADSP released one of its intents
        mMgFree |= 1U << W1;
      } else if ((Cmd == 14 || Cmd == 6) && Ch == 9 && W1 >= 6 && W1 < 12) {
        mMgFree9 |= 1U << (W1 - 6);
      }'''
s = s.replace(old, new, 1)

# 2. MgSend9, ULog helpers (before RtrUcsiRead's comment block)
code = r'''STATIC BOOLEAN
MgSend9 (CONST VOID *Msg, UINT32 Size)
{
  UINT32  Words[40], I, T, Ri = 0xFF;
  UINT32  Padded = (Size + 7) & ~7U;

  for (T = 0; T < 1000 && Ri == 0xFF; T++) {
    MgPoll ();
    for (I = 0; I < 6; I++) {
      if ((mMgFree9 & (1U << I)) != 0) {
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
  mMgFree9 &= ~(1U << Ri);
  SetMem (Words, sizeof (Words), 0);
  Words[0] = 0x00000009 | (9 << 16);
  Words[1] = Ri + 6;
  Words[2] = Size;
  Words[3] = 0;
  CopyMem (Words + 4, Msg, Size);
  MgTxWords (Words, 4 + Padded / 4);
  return TRUE;
}

// ADSP charger ULog (charger-ulog-glink protocol on PMIC_LOGS): request {0x800A, 1, 0x18, 0x2000} -> 12-byte header + up to 8 KB of text.  The ring keeps the FIRST 16 KB after boot and drops later
// lines until it has been read, so drain it once early (UlogDrain) and the later reads (UlogShow) show what happened since.
STATIC UINT32
UlogFetch (VOID)
{
  UINT32  Rq[4], T, Seen = mMgMsgSeq9;

  Rq[0] = 0x800A; Rq[1] = 1; Rq[2] = 0x18; Rq[3] = 0x2000;
  if (!MgSend9 (Rq, 16)) {
    return 0;
  }
  for (T = 0; T < 1500; T++) {
    MgPoll ();
    if (mMgMsgSeq9 != Seen) {
      return mMgMsgLen9 > 12 ? mMgMsgLen9 - 12 : 0;
    }
    gBS->Stall (1000);
  }
  return 0;
}

STATIC VOID
UlogDrain (VOID)
{
  UINT32  I, N, Total = 0;

  for (I = 0; I < 6; I++) {
    N = UlogFetch ();
    Total += N;
    PL ("ULOG drain %u: %u bytes@@NL@@", I, N);
    if (N == 0 || mMgMsg9[12] == 0) {
      break;
    }
  }
}

STATIC VOID
UlogShow (CONST CHAR8 *Tag)
{
  UINT32  N = UlogFetch (), I, L = 0;
  CHAR8   Line[200];

  PL ("ULOG[%a] %u bytes@@NL@@", Tag, N);
  for (I = 0; I < N; I++) {
    UINT8  C = mMgMsg9[12 + I];
    if (C == 0) {
      break;
    }
    if (C == 10 || L >= sizeof (Line) - 1) {
      Line[L] = 0;
      if (L > 0) {
        PL ("ULOG> %a@@NL@@", Line);
      }
      L = 0;
      if (C == 10) {
        continue;
      }
    }
    Line[L++] = (C >= 32 && C < 127) ? (CHAR8)C : '.';
  }
  if (L > 0) {
    Line[L] = 0;
    PL ("ULOG> %a@@NL@@", Line);
  }
}

'''.replace('@@NL@@', NL)
marker = '// UCSI buffer (48 B) in the reply:'
assert marker in s
s = s.replace(marker, code + marker, 1)

# 3. use in RtrHostPrepare: drain at the start, show after attach
old = '  PL ("HOSTPREP: waiting for the PC cable to be unplugged (up to 200 s)' + NL + '");'
assert old in s
s = s.replace(old, '  UlogDrain ();\n' + old, 1)
old = '      PL ("HOSTPREP: device attached, starting Windows' + NL + '");\n      return;'
assert old in s
new = '''      PL ("HOSTPREP: device attached, reading the ADSP log@@NL@@");
      UlogShow ("after-attach-1");
      gBS->Stall (2000000);
      UlogShow ("after-attach-2");
      gBS->Stall (3000000);
      UlogShow ("after-attach-3");
      PL ("HOSTPREP: done, starting Windows@@NL@@");
      return;'''.replace('@@NL@@', NL)
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
