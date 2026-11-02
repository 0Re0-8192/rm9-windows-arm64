"""Mu SEC: right after the firmware banner, print the display registers as the bootloader (ABL) left them -- before any blob driver (SSRDxe, RPMh/clock
init...) can power-collapse the MDSS.  This is the 'golden' working display configuration (MDP/INTF/PP/DSC/DSI/PHY/PLL/RSC/VBIF) to compare with what the stock
DisplayDxe programs later.  Each block is announced before it is read (a gated block hangs the bus -> SEC watchdog bite -> the last line names the block).
Applies on top of patch_sec_wdt.py (run that first).  Idempotent.   usage (WSL): python3 patch_sec_dispgolden.py [on|off] [ssp]
  ssp: also read the SSPP pipe blocks (may hang)"""
import sys
from pathlib import Path

mode = sys.argv[1] if len(sys.argv) > 1 else "on"
ssp = "ssp" in sys.argv[2:]
start = "start" in sys.argv[2:]
p = Path("/root/Mu-Silicium/Silicon/Silicium/SiliciumPkg/Sec/Sec.c")
t = p.read_text(encoding="utf-8")
A = "// RM9 display golden dump begin"
B = "// RM9 display golden dump end"
if A in t:
    a = t.index(A)
    b = t.index(B) + len(B) + 1
    t = t[:a] + t[b:]
    t = t.replace("  RmDispGolden ();\n", "")
if mode == "on":
    ssp_blocks = '    { 0x4000, 0x300, "VIG0" }, { 0x6000, 0x300, "VIG1" }, { 0x24000, 0x300, "DMA0" }, { 0x26000, 0x300, "DMA1" }, { 0x28000, 0x300, "DMA2" },\n' if ssp else ""
    helper = A + "\n" + ("#define DOSTART 1\n" if start else "#define DOSTART 0\n") + r'''
#define RMR(a)  (*(volatile UINT32 *)(UINTN)(a))
STATIC
VOID
RmDispGolden (VOID)
{
  STATIC CONST struct { UINT32 Off; UINT32 Len; CONST CHAR8 *Name; } Blk[] = {
    { 0x0, 0x40, "TOP" }, { 0x100, 0x100, "TOP1" }, { 0x1000, 0x40, "TOP1000" },
    { 0x16000, 0x100, "CTL_0" }, { 0x17000, 0x100, "CTL_1" }, { 0x45000, 0x100, "MIXER_0" }, { 0x46000, 0x100, "MIXER_1" },
    { 0x69000, 0x130, "PP_0" }, { 0x6A000, 0x80, "PP_1" }, { 0x36000, 0x200, "INTF_1" }, { 0x37000, 0x200, "INTF_2" },
    { 0x81000, 0x100, "DSC_0" }, { 0x94000, 0x300, "DSI0" }, { 0x95000, 0x200, "DSIPHY" }, { 0x96000, 0x200, "DSIPLL" },
    { 0x120000, 0x200, "RSC_DRV" }, { 0x130000, 0x80, "RSC_WRAP0" }, { 0x130400, 0x80, "RSC_WRAP4" }, { 0xB0000, 0x80, "VBIF" },
''' + ssp_blocks + r'''  };
  STATIC CONST struct { UINT32 Addr; UINT32 Len; CONST CHAR8 *Name; } Abs[] = {
    { 0x00127000, 0x80, "GCC_DISP" }, { 0x00152000, 0x20, "GCC_52000" }, { 0x0AF00000, 0x20, "DISPCC0" }, { 0x0AF08000, 0x140, "DISPCC8" }, { 0x0AF09000, 0x20, "DISPCC9" },
  };
  UINT32  B, W;
  UINT32  Ver = RMR (0x0AE00000UL);

  DEBUG ((EFI_D_WARN, "[GOLD] MDSS hw_version=0x%08x\n", Ver));
  for (B = 0; B < sizeof (Blk) / sizeof (Blk[0]); B++) {
    DEBUG ((EFI_D_WARN, "[GOLD] block %a @0x%x ...\n", Blk[B].Name, 0x0AE00000UL + Blk[B].Off));
    for (W = 0; W < Blk[B].Len; W += 16) {
      UINT32  A0 = 0x0AE00000UL + Blk[B].Off + W;
      UINT32  V0 = RMR (A0), V1 = RMR (A0 + 4), V2 = RMR (A0 + 8), V3 = RMR (A0 + 12);

      if ((V0 | V1 | V2 | V3) != 0) {
        DEBUG ((EFI_D_WARN, "[GOLD] %a+0x%03x: %08x %08x %08x %08x\n", Blk[B].Name, W, V0, V1, V2, V3));
      }
    }
  }
  for (B = 0; B < sizeof (Abs) / sizeof (Abs[0]); B++) {
    DEBUG ((EFI_D_WARN, "[GOLD] block %a @0x%x ...\n", Abs[B].Name, Abs[B].Addr));
    for (W = 0; W < Abs[B].Len; W += 16) {
      UINT32  A0 = Abs[B].Addr + W;
      UINT32  V0 = RMR (A0), V1 = RMR (A0 + 4), V2 = RMR (A0 + 8), V3 = RMR (A0 + 12);

      if ((V0 | V1 | V2 | V3) != 0) {
        DEBUG ((EFI_D_WARN, "[GOLD] %a+0x%03x: %08x %08x %08x %08x\n", Abs[B].Name, W, V0, V1, V2, V3));
      }
    }
  }
  DEBUG ((EFI_D_WARN, "[GOLD] done\n"));
  if (DOSTART) {
    DEBUG ((EFI_D_WARN, "[GOLD] CTL_0 START ...\n"));
    RMR (0x0AE1601CUL) = 1;
    MicroSecondDelay (1000);
    DEBUG ((EFI_D_WARN, "[GOLD] CTL_0 START written, still alive (flush=0x%08x)\n", RMR (0x0AE16018UL)));
    MicroSecondDelay (100000);
    DEBUG ((EFI_D_WARN, "[GOLD] 100 ms later: still alive\n"));
    for (B = 0; B < sizeof (Blk) / sizeof (Blk[0]); B++) {
      if (AsciiStrnCmp (Blk[B].Name, "VIG", 3) == 0 || AsciiStrnCmp (Blk[B].Name, "DMA", 3) == 0 || AsciiStrnCmp (Blk[B].Name, "MIXER_1", 7) == 0 || AsciiStrnCmp (Blk[B].Name, "TOP1", 4) == 0) {
        continue;
      }
      for (W = 0; W < Blk[B].Len; W += 16) {
        UINT32  A0 = 0x0AE00000UL + Blk[B].Off + W;
        UINT32  V0 = RMR (A0), V1 = RMR (A0 + 4), V2 = RMR (A0 + 8), V3 = RMR (A0 + 12);

        if ((V0 | V1 | V2 | V3) != 0) {
          DEBUG ((EFI_D_WARN, "[POST] %a+0x%03x: %08x %08x %08x %08x\n", Blk[B].Name, W, V0, V1, V2, V3));
        }
      }
    }
    DEBUG ((EFI_D_WARN, "[POST] done\n"));
  }
}
''' + B + "\n"
    old = "STATIC\nVOID\nPrintFirmwareVersion (VOID)\n"
    assert old in t
    t = t.replace(old, helper + "STATIC\nVOID\nPrintFirmwareVersion (VOID)\n", 1)
    old2 = '  DEBUG ((EFI_D_WARN, "Firmware Version %s Build at %a on %a\\n", PcdGetPtr (PcdFirmwareVersionString), __TIME__, __DATE__));\n  DEBUG ((EFI_D_WARN, "\\n"));\n'
    assert old2 in t
    t = t.replace(old2, old2 + "  RmDispGolden ();\n", 1)
    if False:
        t = t.replace("#include <Library/HobLib.h>\n", "#include <Library/HobLib.h>\n#include <Library/IoLib.h>\n", 1)
p.write_text(t, encoding="utf-8")
print("SEC display golden dump:", mode, "(with SSPP)" if ssp else "")


