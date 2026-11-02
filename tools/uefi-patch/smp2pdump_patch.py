p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
bs = chr(92)
code = r'''// SMP2P items of the APPS<->ADSP pair: 443 = ADSP -> APPS, 429 = APPS -> ADSP.  Layout: magic, version/features, local_pid, remote_pid, total_entries, valid_entries, flags, entries[16]{name[16], value}
STATIC VOID
Smp2pDump (CONST CHAR8 *Tag)
{
  UINT32  Sz, K, E;
  UINT16  Items[2] = { 443, 429 };

  for (K = 0; K < 2; K++) {
    UINT32  *P = (UINT32 *)SmemItem (2, Items[K], &Sz);
    if (P == NULL) {
      PL ("SMP2P[%a] item %u: missing" BSN, Tag, Items[K]);
      continue;
    }
    PL ("SMP2P[%a] item %u: magic=%08x ver/feat=%08x pids=%08x entries=%08x flags=%08x" BSN, Tag, Items[K], P[0], P[1], P[2], P[3], P[4]);
    for (E = 0; E < (P[3] >> 16) && E < 16; E++) {
      CHAR8   Name[17];
      UINT32  *Ent = P + 5 + 5 * E;
      UINT32  I;
      for (I = 0; I < 16; I++) {
        UINT8  C = ((UINT8 *)Ent)[I];
        Name[I] = (C >= 0x20 && C < 0x7F) ? (CHAR8)C : '.';
      }
      Name[16] = 0;
      PL ("   %a = 0x%08x" BSN, Name, Ent[4]);
    }
  }
}

'''.replace(' BSN', ' "' + bs + 'n"').replace('" "' + bs + 'n"', bs + 'n"')
marker = '// ADSP.TXT + NOBOOT:'
assert marker in s and 'Smp2pDump' not in s
s = s.replace(marker, code + marker, 1)
s = s.replace('STATIC VOID GlinkFifoDump (CONST CHAR8 *Tag);\n', 'STATIC VOID GlinkFifoDump (CONST CHAR8 *Tag);\nSTATIC VOID Smp2pDump (CONST CHAR8 *Tag);\n', 1)
old = '    GlinkFifoDump ("after-8s");'
assert old in s
s = s.replace(old, old + '\n    Smp2pDump ("after-8s");', 1)
old2 = '  IpccIsrReport ("end");\n  SmemDump ("end");'
assert old2 in s
s = s.replace(old2, '  Smp2pDump ("end");\n' + old2, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
