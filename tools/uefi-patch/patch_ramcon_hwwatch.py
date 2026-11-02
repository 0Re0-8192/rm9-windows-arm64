"""RamConsoleSerialPortLib: log '[HW] mdss=<hw_version>' whenever MDSS hw_version (0xAE00000) differs from the last value this module saw (once the DxeCore START/hw probe has mapped MDSS
and set the flag word 0xD7FF0460 = 'MDSS').  Shows between which two log lines the display power goes away.  Idempotent.  usage (WSL): python3 patch_ramcon_hwwatch.py [on|off]"""
import shutil
import sys
from pathlib import Path

mode = sys.argv[1] if len(sys.argv) > 1 else "on"
p = Path("/root/Mu-Silicium/Platforms/ZTE/nx769jPkg/Library/RamConsoleSerialPortLib/RamConsoleSerialPortLib.c")
o = p.with_suffix(".c.rm9orig")
if not o.exists():
    shutil.copy(p, o)
t = o.read_text(encoding="utf-8")
if mode == "on":
    old = "  InterruptState = ArmGetInterruptState ();\n"
    assert old in t
    add = r'''  {   // RM9 hw watch
    STATIC UINT32  Rm9Prev = 0xFFFFFFFF;

    if (*(volatile UINT32 *)(UINTN)0xD7FF0460ULL == 0x4D445353) {
      UINT32  V = *(volatile UINT32 *)(UINTN)0x0AE00000ULL;

      if (V != Rm9Prev) {
        CHAR8   M[24] = "[HW] mdss=00000000\n";
        UINTN   K;

        Rm9Prev = V;
        for (K = 0; K < 8; K++) {
          UINT32 N = (V >> (28 - 4 * K)) & 0xF;
          M[10 + K] = (CHAR8)(N < 10 ? '0' + N : 'A' + N - 10);
        }
        NxRamConsoleWrite ((UINT8 *)M, 19);
      }
    }
  }
'''
    t = t.replace(old, add + old, 1)
p.write_text(t, encoding="utf-8")
print("RAM console hw watch:", mode)

