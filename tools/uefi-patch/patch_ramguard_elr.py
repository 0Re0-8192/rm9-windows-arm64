"""RamDebugGuardDxe pet timer: also print ELR_EL1 once per second (the interrupted PC) for the first 60 s -> shows where a DXE hang sits."""
from pathlib import Path

p = Path("/root/Mu-Silicium/Platforms/ZTE/nx769jPkg/Drivers/RamDebugGuardDxe/RamDebugGuardDxe.c")
t = p.read_text(encoding="utf-8")
if "RM9_ELR" in t:
    print("already patched")
    raise SystemExit(0)
old = "  A.Arg0 = GH_WDT_PING;\n  ArmCallSmc (&A);\n"
assert old in t
new = old + ("  {  // RM9_ELR\n    UINT64 Elr = 0, Spsr = 0;\n"
             '    __asm__ volatile ("mrs %0, elr_el1"  : "=r" (Elr));\n'
             '    __asm__ volatile ("mrs %0, spsr_el1" : "=r" (Spsr));\n'
             '    DEBUG ((DEBUG_ERROR, "[RAMGUARD] t=%u s elr=0x%lx spsr=0x%lx\\n", mRm9PetCount, Elr, Spsr));\n  }\n')
t = t.replace(old, new, 1)
p.write_text(t, encoding="utf-8")
print("patched")
