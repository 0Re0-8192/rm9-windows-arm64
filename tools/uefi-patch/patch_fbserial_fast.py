"""Mu FrameBufferSerialPortLib: make the on-screen debug console cheap.
 - PcdFrameBufferDelay 10000 us/line -> 0   (SiliciumPkg.dsc.inc)
 - SerialPortWrite flushed the whole 'Display_Reserved' region (44 MB) after EVERY call -> flush only the text rows that were touched
Idempotent; originals kept as *.orig.  usage (WSL): python3 patch_fbserial_fast.py [on|off]"""
import shutil
import sys
from pathlib import Path

mode = sys.argv[1] if len(sys.argv) > 1 else "on"
base = Path("/root/Mu-Silicium/Silicon/Silicium/SiliciumPkg")
c = base / "Library/FrameBufferSerialPortLib/FrameBufferSerialPortLib.c"
d = base / "SiliciumPkg.dsc.inc"
for p in (c, d):
    o = p.with_suffix(p.suffix + ".orig")
    if not o.exists():
        shutil.copy(p, o)
tc = c.with_suffix(".c.orig").read_text(encoding="utf-8")
td = d.with_suffix(".inc.orig").read_text(encoding="utf-8")
if mode == "on":
    old = "  gSiliciumPkgTokenSpaceGuid.PcdFrameBufferDelay|10000          # In Microseconds"
    assert old in td
    td = td.replace(old, "  gSiliciumPkgTokenSpaceGuid.PcdFrameBufferDelay|0              # RM9: was 10000 us per line")
    a = "  // Write Debug Message to Frame Buffer\n  for (UINTN i = 0; i < NumberOfBytes; i++) {"
    assert a in tc
    tc = tc.replace(a, ("  // RM9: remember the text row range that this call touches\n"
                        "  EFI_FRAME_BUFFER_POSITION *Rm9Pos;\n  EFI_FRAME_BUFFER_POSITION  Rm9Max;\n"
                        "  UINT8                      Rm9Scale = GetFontScale ();\n"
                        "  GetFbPositions (FbBase, FbLength, Rm9Scale, &Rm9Pos, &Rm9Max);\n"
                        "  UINT32 Rm9Y0 = Rm9Pos->YPos;\n\n") + a, 1)
    b = "  // Flush Frame Buffer\n  WriteBackInvalidateDataCacheRange ((VOID *)FbBase, FbLength);"
    assert b in tc
    tc = tc.replace(b, ("  // Flush only what was drawn (the old code cleaned the whole 44 MB region on every debug print)\n"
                        "  {\n"
                        "    UINT32 Rm9Y1       = Rm9Pos->YPos;\n"
                        "    UINTN  Rm9RowBytes = (UINTN)(FONT_HEIGHT - 4) * Rm9Scale * FB_WIDTH * FB_BPP;\n"
                        "    if (Rm9Y1 >= Rm9Y0 && (UINTN)(Rm9Y1 + 1) * Rm9RowBytes <= (UINTN)FB_WIDTH * FB_HEIGHT * FB_BPP) {\n"
                        "      WriteBackInvalidateDataCacheRange ((VOID *)(FbBase + (UINTN)Rm9Y0 * Rm9RowBytes), (UINTN)(Rm9Y1 - Rm9Y0 + 1) * Rm9RowBytes);\n"
                        "    } else {\n"
                        "      WriteBackInvalidateDataCacheRange ((VOID *)FbBase, (UINTN)FB_WIDTH * FB_HEIGHT * FB_BPP);\n"
                        "    }\n"
                        "    WriteBackInvalidateDataCacheRange ((VOID *)Rm9Pos, sizeof (*Rm9Pos));\n"
                        "  }"), 1)
c.write_text(tc, encoding="utf-8")
d.write_text(td, encoding="utf-8")
print("fbserial fast:", mode)
