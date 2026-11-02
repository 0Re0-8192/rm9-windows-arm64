p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
bs = chr(92)
code = r'''// UCSI over pmic_glink through PmicGlinkDxe's own TX path: PmicGlinkDxe only sends battmgr messages itself (owner 0x800A/0x800D) but its RX handler already files owner 0x800B (USBC)
// replies into globals: UCSI buffer (48 bytes) at image+0xA258, notification at +0xA288, write ack flags at +0xA2A8/+0xA2A9.  The generic send+poll routine is image+0x42A0(unused, msg, size).
typedef UINTN (EFIAPI *MC_PG_SEND) (UINT32 Unused, VOID *Msg, UINTN Size);

STATIC VOID
UcsiDump (CONST CHAR8 *Tag, CONST UINT8 *B)
{
  PL ("UCSI[%a] ver=%04x cci=%08x ctrl=%016lx in=%08x %08x %08x %08x out=%08x" BSN, Tag, *(CONST UINT16 *)(B + 0), *(CONST UINT32 *)(B + 4), *(CONST UINT64 *)(B + 8),
      *(CONST UINT32 *)(B + 16), *(CONST UINT32 *)(B + 20), *(CONST UINT32 *)(B + 24), *(CONST UINT32 *)(B + 28), *(CONST UINT32 *)(B + 32));
}

STATIC VOID
UcsiCmd (UINT64 Base, CONST CHAR8 *Tag, UINT64 Command)
{
  MC_PG_SEND  Send = (MC_PG_SEND)(UINTN)(Base + 0x42A0);
  UINT8       *Buf = (UINT8 *)(UINTN)(Base + 0xA258);
  UINT8       Req[64];
  UINTN       R;

  // write buffer with the command in CONTROL (offset 8)
  ZeroMem (Req, sizeof (Req));
  ((UINT32 *)Req)[0] = 0x800B;
  ((UINT32 *)Req)[1] = 1;
  ((UINT32 *)Req)[2] = 0x12;
  CopyMem (Req + 12 + 8, &Command, 8);
  R = Send (0, Req, 64);
  PL ("UCSI %a: WRITE_BUF cmd=%016lx -> 0x%lx ack=%u/%u" BSN, Tag, Command, (UINT64)R, *(volatile UINT8 *)(UINTN)(Base + 0xA2A8), *(volatile UINT8 *)(UINTN)(Base + 0xA2A9));
  gBS->Stall (500000);
  // read it back
  SetMem (Buf, 48, 0xEE);
  ZeroMem (Req, sizeof (Req));
  ((UINT32 *)Req)[0] = 0x800B;
  ((UINT32 *)Req)[1] = 1;
  ((UINT32 *)Req)[2] = 0x11;
  R = Send (0, Req, 12);
  PL ("UCSI %a: READ_BUF -> 0x%lx" BSN, Tag, (UINT64)R);
  UcsiDump (Tag, Buf);
}

STATIC VOID
UcsiProbe (UINT64 *P)
{
  UINT64  Base = (UINT64)(UINTN)P - 0xA0B8;

  PL ("UCSI probe: PmicGlinkDxe image base 0x%lx" BSN, Base);
  UcsiCmd (Base, "read", 0);
  UcsiCmd (Base, "ppm-reset", 0x01);
  gBS->Stall (1000000);
  UcsiCmd (Base, "notif-en", 0x05 | (0xFFFFULL << 16) | (1ULL << 8));
  UcsiCmd (Base, "get-cap", 0x06);
  UcsiCmd (Base, "conn1-status", 0x12 | (1ULL << 16));
  if (SelfFileExists (L"BSBSUCSIHOST.TXT")) {
    UcsiCmd (Base, "set-ccom-rp", 0x08 | (1ULL << 16) | (1ULL << 23));
    gBS->Stall (2000000);
    UcsiCmd (Base, "conn1-status-after", 0x12 | (1ULL << 16));
  }
}

'''.replace('BSBS', bs * 2).replace('" BSN', '"' + bs + 'n"').replace('"' + bs + 'n"', bs + 'n"')
# fix: the line above turned ' BSN' into '\n"' - ensure each PL format ends with \n"
marker = '// ADSP.TXT + NOBOOT:'
assert marker in s and 'UcsiProbe' not in s
s = s.replace(marker, code + marker, 1)
old = '  if (R == 0) {\n    PmicGlinkLink ();\n  }'
assert old in s
s = s.replace(old, '  if (R == 0) {\n    PmicGlinkLink ();\n    {\n      EFI_GUID  Gg = { 0x7429EB07, 0xF2E3, 0x4A6B, { 0xAA, 0x96, 0xC9, 0x09, 0xCD, 0x95, 0x6E, 0xF7 } };\n      UINT64    *Pg = NULL;\n      if (!EFI_ERROR (gBS->LocateProtocol (&Gg, NULL, (VOID **)&Pg)) && Pg != NULL) {\n        UcsiProbe (Pg);\n      }\n    }\n  }', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
