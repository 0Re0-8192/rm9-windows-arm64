"""MuChain.c: (1) marker 'EBOK' + CNTVCT after the real ExitBootServices returns,
(2) print DSDT length and whether it contains the DBG0 operation region."""
from pathlib import Path

p = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = p.read_text(encoding="utf-8")

old = "  return mOrigExitBs (ImageHandle, MapKey);\n"
assert old in t, "EBS return not found"
if "EBOK" not in t:
    new = ("  {\n"
           "    EFI_STATUS Es = mOrigExitBs (ImageHandle, MapKey);\n"
           "    UINT64     Cnt;\n"
           "    __asm__ volatile (\"mrs %0, cntvct_el0\" : \"=r\" (Cnt));\n"
           "    if (!EFI_ERROR (Es)) {\n"
           "      *(volatile UINT32 *)(UINTN)0xD7FF00F8ULL = 0x4B4F4245U;   // \"EBOK\"\n"
           "      *(volatile UINT64 *)(UINTN)0xD7FF0100ULL = Cnt;\n"
           "    } else {\n"
           "      *(volatile UINT32 *)(UINTN)0xD7FF00F8ULL = 0x4C494645U;   // \"EFIL\" (EBS failed, retry follows)\n"
           "    }\n"
           "    return Es;\n"
           "  }\n")
    t = t.replace(old, new, 1)

old2 = '          DEBUG ((DEBUG_ERROR, "[MUCHAIN]   FADT: DSDT32=0x%x X_DSDT=0x%lx FACS=0x%x\\n", Dsdt32, Dsdt, *(UINT32 *)(Tab + 36)));'
if old2 in t and "DSDT len" not in t:
    new2 = old2 + ('\n          {\n'
                   '            UINT8  *Ds = (UINT8 *)(UINTN)Dsdt;\n'
                   '            UINT32 Dl  = *(UINT32 *)(Ds + 4);\n'
                   '            UINT32 q;\n'
                   '            BOOLEAN Has = FALSE;\n'
                   '            for (q = 36; q + 4 <= Dl; q++) {\n'
                   '              if (Ds[q] == \'D\' && Ds[q + 1] == \'B\' && Ds[q + 2] == \'G\' && Ds[q + 3] == \'0\') { Has = TRUE; break; }\n'
                   '            }\n'
                   '            DEBUG ((DEBUG_ERROR, "[MUCHAIN]   DSDT len=%u has_DBG0=%u\\n", Dl, (UINT32)Has));\n'
                   '          }')
    t = t.replace(old2, new2, 1)
p.write_text(t, encoding="utf-8")
print("ok", "EBOK" in t, "DSDT len" in t)
