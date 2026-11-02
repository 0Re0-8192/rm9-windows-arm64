p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
BS = chr(92)
NL = BS + 'n'

# 1. RtrUcsiInitOnly after RtrUcsiSession
code = r'''// UCSIINIT.TXT (Windows path too): bring the ADSP's UCSI/PD stack to the state the Linux driver leaves it in (altmode PAN_EN, PPM reset, notifications on),
// then leave the ADSP running on its own: it switches Type-C roles and drives VBUS by itself (hostB: device attached -> Source/DFP).
STATIC VOID
RtrUcsiInitOnly (VOID)
{
  UINT8   B[48];
  UINT32  Pan[4];

  if (mIpccTimer != NULL) {
    gBS->SetTimer (mIpccTimer, TimerCancel, 0);
  }
  gBS->Stall (200000);
  if (!MgInit ()) {
    PL ("UCSI.INIT: mini glink init failed@@NL@@");
    return;
  }
  Pan[0] = 0x800C; Pan[1] = 1; Pan[2] = 0x15; Pan[3] = 1;
  MgSend (Pan, 16);
  gBS->Stall (200000);
  if (!RtrUcsiRead (B)) {
    PL ("UCSI.INIT: first read failed@@NL@@");
    return;
  }
  RtrUcsiShow ("init-read", B);
  RtrUcsiCmd ("init-ppm-reset", 0x01, B);
  RtrUcsiCmd ("init-notif-en", 0x05 | (0x8001ULL << 16), B);
  RtrUcsiCmd ("init-conn1-status", 0x12 | (1ULL << 16), B);
}

'''.replace('@@NL@@', NL)
marker = 'STATIC VOID\nUcsiCmd (UINT64 Base, CONST CHAR8 *Tag, UINT64 Command)'
assert marker in s
s = s.replace(marker, code + marker, 1)

# 2. call from AdspLoad instead of UcsiProbe when UCSIINIT.TXT exists
old = '''      if (!EFI_ERROR (gBS->LocateProtocol (&Gg, NULL, (VOID **)&Pg)) && Pg != NULL) {
        UcsiProbe (Pg);
      }'''
assert old in s
new = '''      if (SelfFileExists (L"''' + BS * 2 + '''UCSIINIT.TXT")) {
        RtrUcsiInitOnly ();
      } else if (!EFI_ERROR (gBS->LocateProtocol (&Gg, NULL, (VOID **)&Pg)) && Pg != NULL) {
        UcsiProbe (Pg);
      }'''
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)

# 3. scripts
q = '<RM9_WORKDIR>/refs/make_logdump_img.sh'
t = open(q, encoding='utf-8', newline='').read()
t = t.replace('if [ "${15}" = rtr ]; then echo 1 > /mnt/m/RTR.TXT; fi\n', 'if [ "${15}" = rtr ]; then echo 1 > /mnt/m/RTR.TXT; fi\nif [ "${16}" = ucsiinit ]; then echo 1 > /mnt/m/UCSIINIT.TXT; fi   # AdspLoad: only the UCSI init (reset + notifications), no probing\n', 1)
open(q, 'w', encoding='utf-8', newline='').write(t)
q = '<RM9_WORKDIR>/refs/build_muchain.sh'
t = open(q, encoding='utf-8', newline='').read()
t = t.replace('"${14}" "${15}"', '"${14}" "${15}" "${16}"', 1)
open(q, 'w', encoding='utf-8', newline='').write(t)
q = '<RM9_WORKDIR>/refs/phone_setup_loop.ps1'
t = open(q, encoding='utf-8', newline='').read()
old = "$(if ($Adsp) { 'adsp' } else { '-' }) | Select-Object"
assert old in t
t = t.replace(old, "$(if ($Adsp) { 'adsp' } else { '-' }) - - - $(if ($Adsp) { 'ucsiinit' } else { '-' }) | Select-Object", 1)
open(q, 'w', encoding='utf-8', newline='').write(t)
print('ok')
