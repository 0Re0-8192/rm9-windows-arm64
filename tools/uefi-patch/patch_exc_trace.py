"""Mu exception handler: turn 'brk #imm' (imm != 1) into a non-halting call trace point.
A patched `bl target` becomes `brk #disp16` (disp16 = (target - site) / 4, signed).  The handler prints
  [TR] pc=<site> -> <target> x0 x1 x2 x3
emulates the call (LR = site + 4, ELR = target) and returns; brk #1 keeps its halting behaviour.
Idempotent; original kept as .rm9orig (shared with patch_exc_dispdiag.py: run that one first / after, both work on the .rm9orig copy only if
you re-run both).   usage (WSL): python3 patch_exc_trace.py [on|off]"""
import shutil
import sys
from pathlib import Path

mode = sys.argv[1] if len(sys.argv) > 1 else "on"
START = "start" in sys.argv[2:]
p = Path("/root/Mu-Silicium/Mu_Basecore/UefiCpuPkg/Library/CpuExceptionHandlerLib/AArch64/CpuExceptionHandlerLib.c")
o = p.with_suffix(".c.rm9orig")
if not o.exists():
    shutil.copy(p, o)
t = p.read_text(encoding="utf-8")
MARK = "RM9 call trace"
if mode == "off":
    if MARK in t:
        a = t.index("  // " + MARK)
        b = t.index("  // end " + MARK) + len("  // end " + MARK + "\n")
        t = t[:a] + t[b:]
else:
    if MARK not in t:
        old = "  if ((UINTN)ExceptionType <= mMaxExceptionNumber) {\n    if (mExceptionHandlers[ExceptionType] != NULL) {"
        assert old in t
        add = r'''  // RM9 call trace
  if (ExceptionType == EXCEPT_AARCH64_SYNCHRONOUS_EXCEPTIONS) {
    UINT64  Rm9Esr = SystemContext.SystemContextAArch64->ESR;

    if ((((Rm9Esr >> 26) & 0x3F) == 0x3C) && ((Rm9Esr & 0xFFFF) != 1)) {
      CHAR8   Rm9Buf[160];
      UINTN   Rm9N;
      UINT64  Rm9Pc = SystemContext.SystemContextAArch64->ELR;
      INT64   Rm9Disp = (((Rm9Esr & 0xFFFF) >= 0x8000) && ((Rm9Esr & 0xFFFF) < 0xC000)) ? (INT64)mRm9Far[(Rm9Esr & 0xFFFF) - 0x8000] : (INT64)(INT16)(Rm9Esr & 0xFFFF);

      Rm9N = AsciiSPrint (Rm9Buf, sizeof (Rm9Buf), "[TR] %lx -> %lx %lx %lx %lx %lx\n", Rm9Pc, Rm9Pc + Rm9Disp * 4,
                          SystemContext.SystemContextAArch64->X0, SystemContext.SystemContextAArch64->X1,
                          SystemContext.SystemContextAArch64->X2, SystemContext.SystemContextAArch64->X3);
      SerialPortWrite ((UINT8 *)Rm9Buf, Rm9N);
RM9_START_HOOK      SystemContext.SystemContextAArch64->LR  = Rm9Pc + 4;
      SystemContext.SystemContextAArch64->ELR = Rm9Pc + Rm9Disp * 4;
      return;
    }
  }
  // end RM9 call trace
'''
        add = add.replace("RM9_START_HOOK", "      *(volatile UINT32 *)(UINTN)0x0AE1601CULL = 1;   // CTL_0 START at every trace point\n" if START else "")
        t = t.replace(old, add + old, 1)
        anchor = "VOID\nEFIAPI\nCommonCExceptionHandler ("
        assert anchor in t
        t = t.replace(anchor, "STATIC CONST INT32  mRm9Far[] = { /* RM9FAR */ 0 /* END RM9FAR */ };\n\n" + anchor, 1)
p.write_text(t, encoding="utf-8")
print("exception call trace:", mode)
