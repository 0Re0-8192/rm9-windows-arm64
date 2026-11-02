"""MuChain: CmdDbProbe() - READ-ONLY dump of the RPMh command database (shared memory at 0x81C60000, written by AOP).
Layout (Linux cmd-db.c): header: version u32, magic db 30 03 0c, rsc_hdr[8] x16B {slv_id u16, header_offset u16, data_offset u16, cnt u16, version u16, rsv}, data[] at +144.
entry_header 24 B: id[8], priority[2] u32, addr u32, len u16, offset u16."""
from pathlib import Path

c = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = c.read_text(encoding="utf-8")
assert "CmdDbProbe" not in t
fn = r'''
STATIC VOID
CmdDbProbe (VOID)
{
  CONST UINT8  *H = (CONST UINT8 *)(UINTN)0x81C60000ULL;
  UINT32       I, J, Total = 0;

  DEBUG ((DEBUG_ERROR, "[MUCHAIN] CMDDB hdr: version=0x%x magic=%02x %02x %02x %02x\n", *(CONST UINT32 *)H, H[4], H[5], H[6], H[7]));
  if (H[4] != 0xdb || H[5] != 0x30 || H[6] != 0x03 || H[7] != 0x0c) {
    return;
  }
  for (I = 0; I < 8; I++) {
    CONST UINT8  *R = H + 8 + 16 * I;
    UINT16       SlvId = *(CONST UINT16 *)(R + 0), HdrOff = *(CONST UINT16 *)(R + 2), Cnt = *(CONST UINT16 *)(R + 6);
    CONST UINT8  *E;

    if (SlvId == 0) {
      break;
    }
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] CMDDB slave %u: entries=%u (hdr off 0x%x)\n", SlvId, Cnt, HdrOff));
    E = H + 144 + HdrOff;
    for (J = 0; J < Cnt; J++, E += 24) {
      CHAR8  Name[9];
      UINT32 K;
      for (K = 0; K < 8; K++) {
        Name[K] = (E[K] >= 0x20 && E[K] < 0x7F) ? (CHAR8)E[K] : (E[K] == 0 ? 0 : '?');
      }
      Name[8] = 0;
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] CMDDB s%u %-8a addr=0x%05x len=%u\n", SlvId, Name, *(CONST UINT32 *)(E + 16), *(CONST UINT16 *)(E + 20)));
      Total++;
    }
  }
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] CMDDB total entries=%u\n", Total));
}
'''
t = t.replace("\nSTATIC VOID\nDumpMemMap (VOID)", fn + "\nSTATIC VOID\nDumpMemMap (VOID)", 1)
old = "  SpmiProbe ();\n"
assert old in t
t = t.replace(old, old + "  CmdDbProbe ();\n", 1)
c.write_text(t, encoding="utf-8")
print("ok")
