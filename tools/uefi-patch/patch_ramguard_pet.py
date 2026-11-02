"""Mu RamDebugGuardDxe: keep feeding the Gunyah watchdog from a 1 s timer for the first 60 s after the driver loads.
Why: Sec.c arms a ~31 s watchdog first thing; nothing fed it until MuChain loaded, so a DXE phase that took >31 s (it varies a lot,
slow on-screen log) ended in a watchdog bite at a random driver.  MuChain takes over the watchdog when it loads; after 60 s this timer
stops by itself so MuChain's own safety cut-offs (NOBOOT 12 s, normal 180 s) still work.
Idempotent.  usage (WSL): python3 patch_ramguard_pet.py"""
from pathlib import Path

p = Path("/root/Mu-Silicium/Platforms/ZTE/nx769jPkg/Drivers/RamDebugGuardDxe/RamDebugGuardDxe.c")
t = p.read_text(encoding="utf-8")
if "RM9_PET" in t:
    print("already patched")
    raise SystemExit(0)
helper = r'''
// RM9_PET: periodic watchdog feeding during DXE (first 60 s only)
STATIC UINT32 mRm9PetCount;

STATIC VOID EFIAPI
Rm9PetTimer (EFI_EVENT Event, VOID *Context)
{
  ARM_SMC_ARGS A = { 0 };
  (VOID)Context;
  A.Arg0 = GH_WDT_PING;
  ArmCallSmc (&A);
  if (++mRm9PetCount >= 60) {
    gBS->SetTimer (Event, TimerCancel, 0);
  }
}

'''
anchor = "EFI_STATUS EFIAPI\nRamDebugGuardEntry"
assert anchor in t
t = t.replace(anchor, helper + anchor, 1)
old = '  DEBUG ((DEBUG_ERROR, "[RAMGUARD] ARMED; no periodic pet from this driver\\n"));\n'
assert old in t
new = old + ('  {\n    EFI_EVENT Rm9Ev = NULL;\n'
             '    Status = gBS->CreateEvent (EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, Rm9PetTimer, NULL, &Rm9Ev);\n'
             '    if (!EFI_ERROR (Status)) {\n'
             '      Status = gBS->SetTimer (Rm9Ev, TimerPeriodic, 10000000);\n'
             '    }\n'
             '    DEBUG ((DEBUG_ERROR, "[RAMGUARD] RM9 1 s pet timer (60 s): %r\\n", Status));\n  }\n')
t = t.replace(old, new, 1)
p.write_text(t, encoding="utf-8")
print("patched")
