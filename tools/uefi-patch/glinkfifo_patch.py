p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
bs = chr(92)
code = r'''// APPS<->ADSP SMEM partition (hosts 0 and 2): locate items by walking the private entries, then show the glink-native descriptor (item 478) and the two FIFOs (479 / 480)
STATIC UINT8 *
SmemItem (UINT16 Host1, UINT16 Item, UINT32 *OutSize)
{
  UINT64  B = 0x81D00000ULL, Sz = 0x200000ULL;
  UINT8   *Pt = (UINT8 *)(UINTN)(B + Sz - 4096);
  UINT32  I, N = *(UINT32 *)(Pt + 8);

  for (I = 0; I < N && I < 32; I++) {
    UINT8   *E = Pt + 32 + 48 * I;
    UINT32  Off = *(UINT32 *)(E + 0), Size = *(UINT32 *)(E + 4);
    UINT16  H0 = *(UINT16 *)(E + 12), H1 = *(UINT16 *)(E + 14);
    if (Off != 0 && Size != 0 && H0 == 0 && H1 == Host1) {
      UINT8  *H = (UINT8 *)(UINTN)(B + Off);
      UINT32 Free = *(UINT32 *)(H + 8);
      UINT8  *Ent = H + 32;
      while (Ent < H + Free) {
        UINT16  Canary = *(UINT16 *)Ent, It = *(UINT16 *)(Ent + 2);
        UINT32  ESize = *(UINT32 *)(Ent + 4);
        UINT16  PadHdr = *(UINT16 *)(Ent + 10);
        if (Canary != 0xA5A5) {
          break;
        }
        if (It == Item) {
          if (OutSize != NULL) {
            *OutSize = ESize;
          }
          return Ent + 16 + PadHdr;
        }
        Ent += 16 + PadHdr + ESize;
      }
    }
  }
  return NULL;
}

STATIC VOID
GlinkFifoDump (CONST CHAR8 *Tag)
{
  UINT32  Sz;
  UINT32  *D = (UINT32 *)SmemItem (2, 478, &Sz);
  UINT8   *F0 = SmemItem (2, 479, &Sz);
  UINT8   *F1 = SmemItem (2, 480, &Sz);
  UINT32  I;

  if (D == NULL) {
    PL ("GLINKFIFO[%a] no descriptor" BSN, Tag);
    return;
  }
  PL ("GLINKFIFO[%a] desc@%p: %08x %08x %08x %08x %08x %08x %08x %08x" BSN, Tag, D, D[0], D[1], D[2], D[3], D[4], D[5], D[6], D[7]);
  for (I = 0; I < 2; I++) {
    UINT8  *F = I == 0 ? F0 : F1;
    if (F != NULL) {
      UINT32  *W = (UINT32 *)F;
      PL ("GLINKFIFO[%a] fifo%u@%p: %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x" BSN, Tag, I, F, W[0], W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11]);
    }
  }
}

'''.replace(' BSN', ' "' + bs + 'n"').replace('" "' + bs + 'n"', bs + 'n"')
marker = '// ADSP.TXT + NOBOOT:'
assert marker in s and 'GlinkFifoDump' not in s
s = s.replace(marker, code + marker, 1)
s = s.replace('STATIC VOID SmemDump (CONST CHAR8 *Tag);\n', 'STATIC VOID SmemDump (CONST CHAR8 *Tag);\nSTATIC VOID GlinkFifoDump (CONST CHAR8 *Tag);\n', 1)
# dumps: after the 8 s wait, after PmicGlink connect, after each UCSI write
old = '    SmemDump ("after-8s");'
assert old in s
s = s.replace(old, old + '\n    GlinkFifoDump ("after-8s");', 1)
old = '  PL ("UCSI %a: READ_BUF -> 0x%lx' + bs + 'n", Tag, (UINT64)R);'
assert old in s
s = s.replace(old, old + '\n  GlinkFifoDump (Tag);', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
