"""Mu exception handler: print a few MDSS/dispcc/DSI registers right after 'Exception at ...' so a BRK dump shows the display clock state at that moment.
Idempotent; original kept as .rm9orig.   usage (WSL): python3 patch_exc_dispdiag.py [on|off]"""
import shutil
import sys
from pathlib import Path

mode = sys.argv[1] if len(sys.argv) > 1 else "on"
p = Path("/root/Mu-Silicium/Mu_Basecore/UefiCpuPkg/Library/CpuExceptionHandlerLib/AArch64/CpuExceptionHandlerLib.c")
o = p.with_suffix(".c.rm9orig")
if not o.exists():
    shutil.copy(p, o)
t = o.read_text(encoding="utf-8")
if mode == "on":
    old = "  UnicodeSPrintAsciiFormat (UnicodeBuffer, MAX_PRINT_CHARS, Buffer);\n"
    assert old in t
    add = old + r'''
  {  // RM9 display diag (read-only MMIO)
    CHAR8   Rm9Buf[256];
    UINTN   Rm9N;
    volatile UINT32  *Mdss = (volatile UINT32 *)(UINTN)0x0AE00000ULL;
    volatile UINT32  *Dcc  = (volatile UINT32 *)(UINTN)0x0AF00000ULL;
    Rm9N = AsciiSPrint (Rm9Buf, sizeof (Rm9Buf), "[EXC] mdss=0x%08x dispcc pll=0x%08x ahb=0x%08x mdp=0x%08x byte0=0x%08x intf=0x%08x pclk0=0x%08x gdsc=0x%08x\n",
                        Mdss[0], Dcc[0], Dcc[0x80A4 / 4], Dcc[0x8038 / 4], Dcc[0x8028 / 4], Dcc[0x802C / 4], Dcc[0x8004 / 4], Dcc[0x9000 / 4]);
    SerialPortWrite ((UINT8 *)Rm9Buf, Rm9N);
  }
'''
    t = t.replace(old, add, 1)
p.write_text(t, encoding="utf-8")
print("exception display diag:", mode)
