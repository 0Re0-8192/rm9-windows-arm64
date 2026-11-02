p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
bs = chr(92)
code = r'''// SMEM overview (read-only): global TOC allocations of items 400..500 and the private partitions (ptable at base+size-4K), to see which smp2p / glink items exist
STATIC VOID
SmemDump (CONST CHAR8 *Tag)
{
  UINT64  B = 0x81D00000ULL, Sz = 0x200000ULL;
  UINT32  I, N;
  UINT8   *Pt = (UINT8 *)(UINTN)(B + Sz - 4096);

  PL ("SMEM[%a] ptable magic=%08x version=%u entries=%u" BSN, Tag, *(UINT32 *)Pt, *(UINT32 *)(Pt + 4), *(UINT32 *)(Pt + 8));
  N = *(UINT32 *)(Pt + 8);
  for (I = 0; I < N && I < 16; I++) {
    UINT8   *E = Pt + 32 + 32 * I;
    UINT32  Off = *(UINT32 *)(E + 0), Size = *(UINT32 *)(E + 4);
    UINT16  H0 = *(UINT16 *)(E + 12), H1 = *(UINT16 *)(E + 14);
    UINT8   *H;
    UINT8   *Ent;
    UINT32  Free, Cnt = 0;

    PL ("SMEM[%a] part%u: hosts %u<->%u offset=0x%x size=0x%x" BSN, Tag, I, H0, H1, Off, Size);
    if (Size == 0 || Off == 0 || (H0 != 0 && H1 != 0)) {
      continue;
    }
    H = (UINT8 *)(UINTN)(B + Off);
    Free = *(UINT32 *)(H + 8);
    PL ("   $PRT magic=%08x host %u/%u size=0x%x free_uncached=0x%x" BSN, *(UINT32 *)H, *(UINT16 *)(H + 4), *(UINT16 *)(H + 6), *(UINT32 *)(H + 8 - 4 + 4 - 4 + 4), Free);
    Ent = H + 32;
    while (Ent < H + Free && Cnt < 40) {
      UINT16  Canary = *(UINT16 *)Ent, Item = *(UINT16 *)(Ent + 2);
      UINT32  ESize = *(UINT32 *)(Ent + 4);
      UINT16  PadData = *(UINT16 *)(Ent + 8), PadHdr = *(UINT16 *)(Ent + 10);
      if (Canary != 0xA5A5) {
        PL ("   bad canary %04x at +0x%x" BSN, Canary, (UINT32)(Ent - H));
        break;
      }
      PL ("   item %u size=%u (pad %u)" BSN, Item, ESize, PadData);
      Ent += 16 + PadHdr + ESize;
      Cnt++;
    }
  }
  {
    UINT8   *G = (UINT8 *)(UINTN)B;
    UINT32  Item;
    for (Item = 400; Item < 500; Item++) {
      UINT32  *T = (UINT32 *)(G + 0x10 + 4 * 32 + 16 + 4 * 4 + 0);   // placeholder, replaced below
      (VOID)T;
    }
    // smem_header: proc_comm[4] (16 B each) = 64, version[32] = 128, initialized, free_offset, available, reserved = 16 -> toc at 0xD0, entries 16 B
    for (Item = 400; Item < 500; Item++) {
      UINT32  *T = (UINT32 *)(G + 0xD0 + 16 * Item);
      if (T[0] != 0) {
        PL ("SMEM[%a] global item %u: offset=0x%x size=%u" BSN, Tag, Item, T[1], T[2]);
      }
    }
  }
}

'''.replace(' BSN', ' "' + bs + 'n"').replace('" "' + bs + 'n"', bs + 'n"')
code = code.replace('"\n"', '\n"')
marker = '// ADSP.TXT + NOBOOT:'
assert marker in s and 'SmemDump' not in s
s = s.replace(marker, code + marker, 1)
s = s.replace('STATIC VOID IpccCfgScan (VOID);\n', 'STATIC VOID IpccCfgScan (VOID);\nSTATIC VOID SmemDump (CONST CHAR8 *Tag);\n', 1)
old = '    IpccIsrReport ("after-8s");'
assert old in s
s = s.replace(old, old + '\n    SmemDump ("after-8s");', 1)
old2 = '  IpccIsrReport ("end");\n  IpccDxeDump ();'
assert old2 in s
s = s.replace(old2, '  IpccIsrReport ("end");\n  SmemDump ("end");\n  IpccDxeDump ();', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
