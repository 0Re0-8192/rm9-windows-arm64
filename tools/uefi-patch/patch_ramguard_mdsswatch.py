"""Mu RamDebugGuardDxe: watch MDSS (0xAE00000 hw_version) every 5 ms for the first 60 s and log every change, so the RAM console shows between
which two DXE drivers the display power disappears.   Idempotent.   usage (WSL): python3 patch_ramguard_mdsswatch.py"""
from pathlib import Path

p = Path("/root/Mu-Silicium/Platforms/ZTE/nx769jPkg/Drivers/RamDebugGuardDxe/RamDebugGuardDxe.c")
t = p.read_text(encoding="utf-8")
if "RM9_MDSSWATCH" in t:
    print("already patched")
    raise SystemExit(0)
helper = r'''
// RM9_MDSSWATCH: log every change of MDSS hw_version (0xAE00000); 0 = display power gone
STATIC UINT32 mRm9MdssLast = 0xDEADBEEF;
STATIC UINT32 mRm9MdssTicks;

STATIC VOID EFIAPI
Rm9MdssTimer (EFI_EVENT Event, VOID *Context)
{
  UINT32 V = *(volatile UINT32 *)(UINTN)0x0AE00000ULL;
  (VOID)Context;
  if (V != mRm9MdssLast) {
    DEBUG ((DEBUG_ERROR, "[RAMGUARD] MDSS hw_version 0x%08x -> 0x%08x at tick %u (5 ms)\n", mRm9MdssLast, V, mRm9MdssTicks));
    mRm9MdssLast = V;
  }
  if (++mRm9MdssTicks >= 12000) {
    gBS->SetTimer (Event, TimerCancel, 0);
  }
}

'''
anchor = "EFI_STATUS EFIAPI\nRamDebugGuardEntry"
assert anchor in t
t = t.replace(anchor, helper + anchor, 1)
old = '    DEBUG ((DEBUG_ERROR, "[RAMGUARD] RM9 1 s pet timer (60 s): %r\\n", Status));\n  }\n'
assert old in t
new = old + ('  {\n    EFI_EVENT Rm9Ev2 = NULL;\n'
             '    Status = gBS->CreateEvent (EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, Rm9MdssTimer, NULL, &Rm9Ev2);\n'
             '    if (!EFI_ERROR (Status)) {\n'
             '      Status = gBS->SetTimer (Rm9Ev2, TimerPeriodic, 50000);\n'
             '    }\n'
             '    DEBUG ((DEBUG_ERROR, "[RAMGUARD] RM9 MDSS watch timer: %r\\n", Status));\n  }\n')
t = t.replace(old, new, 1)
p.write_text(t, encoding="utf-8")
print("patched")
