p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
BS = chr(92)
NL = BS + 'n'
code = r'''// UCSIHOST.TXT: make the phone a USB host / VBUS source on connector 1 through the ADSP (UCSI), after the PC cable has been removed and an OTG adapter + device is plugged in.
STATIC BOOLEAN  mRtrQuiet;

STATIC UINT32
RtrConnStatus (UINT32 *W0, UINT32 *W1)
{
  UINT8   B[48];
  UINT32  Cci;

  mRtrQuiet = TRUE;
  Cci = RtrUcsiCmd ("st", 0x12 | (1ULL << 16), B);
  mRtrQuiet = FALSE;
  *W0 = *(UINT32 *)(B + 16);
  *W1 = *(UINT32 *)(B + 20);
  return Cci;
}

STATIC VOID
RtrUcsiHostTest (VOID)
{
  UINT32  T, W0, W1, L0 = 0xFFFFFFFF, L1 = 0xFFFFFFFF, Cci;
  UINT8   B[48];
  BOOLEAN Gone = FALSE;

  PL ("HOSTTEST: step 1 - waiting for the PC cable to be unplugged (up to 150 s)@@NL@@");
  for (T = 0; T < 150; T++) {
    Cci = RtrConnStatus (&W0, &W1);
    if (W0 != L0 || W1 != L1) {
      PL ("HOSTTEST: t=%u cci=%08x status=%08x %08x connected=%u powerdir=%u opmode=%u@@NL@@", T, Cci, W0, W1, (W0 >> 19) & 1, (W0 >> 20) & 1, (W0 >> 16) & 7);
      L0 = W0; L1 = W1;
    }
    if (((W0 >> 19) & 1) == 0) {
      Gone = TRUE;
      break;
    }
    gBS->Stall (1000000);
  }
  PL ("HOSTTEST: cable gone=%u -> step 2: Rp-only (source), PDR source, UOR DFP@@NL@@", Gone);
  RtrUcsiCmd ("set-ccom-rp", 0x08 | (1ULL << 16) | (1ULL << 23), B);
  RtrUcsiCmd ("set-pdr-source", 0x0B | (1ULL << 16) | (1ULL << 23), B);
  RtrUcsiCmd ("set-uor-dfp", 0x09 | (1ULL << 16) | (1ULL << 23), B);
  PL ("HOSTTEST: step 3 - waiting for a device to be attached (up to 240 s)@@NL@@");
  L0 = 0xFFFFFFFF; L1 = 0xFFFFFFFF;
  for (T = 0; T < 240; T++) {
    Cci = RtrConnStatus (&W0, &W1);
    if (W0 != L0 || W1 != L1) {
      PL ("HOSTTEST: t=%u cci=%08x status=%08x %08x connected=%u powerdir=%u opmode=%u@@NL@@", T, Cci, W0, W1, (W0 >> 19) & 1, (W0 >> 20) & 1, (W0 >> 16) & 7);
      L0 = W0; L1 = W1;
    }
    gBS->Stall (1000000);
  }
  PL ("HOSTTEST: step 4 - restore DRP@@NL@@");
  RtrUcsiCmd ("set-ccom-drp", 0x08 | (1ULL << 16) | (4ULL << 23), B);
  RtrUcsiCmd ("set-pdr-sink", 0x0B | (1ULL << 16) | (2ULL << 23), B);
  RtrUcsiCmd ("set-uor-ufp", 0x09 | (1ULL << 16) | (2ULL << 23), B);
  RtrConnStatus (&W0, &W1);
  PL ("HOSTTEST: end status=%08x %08x@@NL@@", W0, W1);
}

'''.replace('@@NL@@', NL)
marker = 'STATIC VOID\nRtrUcsiSession (VOID)'
assert marker in s
s = s.replace(marker, code + marker, 1)
# quiet flag in RtrUcsiCmd's show
old = '  RtrUcsiShow (Tag, B);\n  if (Out48 != NULL) {'
assert old in s
s = s.replace(old, '  if (!mRtrQuiet) {\n    RtrUcsiShow (Tag, B);\n  }\n  if (Out48 != NULL) {', 1)
# declare mRtrQuiet before RtrUcsiCmd: move declaration up
s = s.replace('STATIC BOOLEAN  mRtrQuiet;\n\nSTATIC UINT32\nRtrConnStatus', 'STATIC UINT32\nRtrConnStatus', 1)
s = s.replace('// UCSI buffer (48 B) in the reply:', 'STATIC BOOLEAN  mRtrQuiet;\n\n// UCSI buffer (48 B) in the reply:', 1)
# call it at the end of RtrUcsiSession
old2 = '  RtrUcsiCmd ("conn2-status", 0x12 | (2ULL << 16), B);\n}'
assert old2 in s
s = s.replace(old2, '  RtrUcsiCmd ("conn2-status", 0x12 | (2ULL << 16), B);\n  if (SelfFileExists (L"' + BS * 2 + 'UCSIHOST.TXT")) {\n    RtrUcsiHostTest ();\n  }\n}', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
