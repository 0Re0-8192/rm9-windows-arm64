"""MuChain UfsProbe: also dump the firmware driver's UTRL slots / first UCD (read-only memory reads)."""
from pathlib import Path

c = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = c.read_text(encoding="utf-8")
assert "UFSTRL" not in t
anchor = '''              *(volatile UINT32 *)(UINTN)(Base + Reg[K].Off)));
    }
  }
}
'''
assert anchor in t
add = '''              *(volatile UINT32 *)(UINTN)(Base + Reg[K].Off)));
    }
    {
      UINT64 Utrl = ((UINT64)*(volatile UINT32 *)(UINTN)(Base + 0x54) << 32) | *(volatile UINT32 *)(UINTN)(Base + 0x50);
      UINTN  Slot, W;
      if (Utrl >= 0x80000000ULL && Utrl < 0x100000000ULL) {
        for (Slot = 0; Slot < 32; Slot++) {
          volatile UINT32 *D = (volatile UINT32 *)(UINTN)(Utrl + Slot * 32);
          UINT32          Any = 0;
          for (W = 0; W < 8; W++) { Any |= D[W]; }
          if (Any != 0) {
            UINT64 Ucd = ((UINT64)D[5] << 32) | D[4];
            DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSTRL slot %lu: %08x %08x %08x %08x ucd=0x%lx %08x %08x\\n", (UINT64)Slot,
                    D[0], D[1], D[2], D[3], Ucd, D[6], D[7]));
            if (Slot == 0 && Ucd >= 0x80000000ULL && Ucd < 0x100000000ULL) {
              volatile UINT32 *U = (volatile UINT32 *)(UINTN)Ucd;
              for (W = 0; W < 24; W += 4) {
                DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSUCD0 +0x%02x: %08x %08x %08x %08x\\n", (UINT32)(W * 4), U[W], U[W + 1], U[W + 2], U[W + 3]));
              }
            }
          }
        }
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSTRL dump done (list at 0x%lx)\\n", Utrl));
      }
    }
  }
}
'''
t = t.replace(anchor, add, 1)
c.write_text(t, encoding="utf-8")
print("ok")
