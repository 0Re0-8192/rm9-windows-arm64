# -*- coding: utf-8 -*-
"""Add GH watchdog arming to MuProbe before its halt (so the crash-capture
path engages); include ArmSmcLib."""
from pathlib import Path

OUT = Path(r"<RM9_WORKDIR>_extra\codex_work\files-mentioned-by-the-user-01\outputs\bringup-20261012-ufs")

c = OUT / "MuProbe.c"
s = c.read_text(encoding="utf-8")

old_inc = "#include <Library/DevicePathLib.h>"
assert old_inc in s, "include not found"
if "ArmSmcLib.h" not in s:
    s = s.replace(old_inc, old_inc + "\n#include <Library/ArmSmcLib.h>", 1)

old = """  DEBUG ((DEBUG_ERROR, "[MUPROBE] done; CPU halt for later RAM capture\\n"));
  Print (L"[MUPROBE] done. HALT (power-cycle to recover)\\n");
  CpuDeadLoop ();"""

new = """  DEBUG ((DEBUG_ERROR, "[MUPROBE] done; arming watchdog and halting for crash-capture\\n"));
  Print (L"[MUPROBE] done. HALT for capture\\n");
  {
    ARM_SMC_ARGS Args = { 0 };
    INT64        CallStatus;

    Args.Arg0 = 0x86000005U;  // GH_WDT_CONTROL
    Args.Arg1 = 2;
    ArmCallSmc (&Args);
    CallStatus = (INT64)Args.Arg0;
    DEBUG ((DEBUG_ERROR, "[MUPROBE] GH_WDT DISABLE ret=%ld\\n", CallStatus));
    if (CallStatus == 0) {
      Args.Arg0 = 0x86000008U;  // GH_WDT_SET_TIME
      Args.Arg1 = 30000;
      Args.Arg2 = 30000;
      ArmCallSmc (&Args);
      CallStatus = (INT64)Args.Arg0;
      DEBUG ((DEBUG_ERROR, "[MUPROBE] GH_WDT SET_TIME ret=%ld\\n", CallStatus));
    }
    if (CallStatus == 0) {
      Args.Arg0 = 0x86000005U;
      Args.Arg1 = 3;
      Args.Arg2 = 0;
      ArmCallSmc (&Args);
      CallStatus = (INT64)Args.Arg0;
      DEBUG ((DEBUG_ERROR, "[MUPROBE] GH_WDT ENABLE ret=%ld\\n", CallStatus));
    }
    if (CallStatus == 0) {
      Args.Arg0 = 0x86000007U;  // GH_WDT_PING
      Args.Arg1 = 0;
      Args.Arg2 = 0;
      ArmCallSmc (&Args);
      CallStatus = (INT64)Args.Arg0;
      DEBUG ((DEBUG_ERROR, "[MUPROBE] GH_WDT PING ret=%ld\\n", CallStatus));
    }
    DEBUG ((DEBUG_ERROR, "[MUPROBE] watchdog path done (ret=%ld); CPU halt\\n", CallStatus));
  }
  CpuDeadLoop ();"""

assert old in s, "halt block not found"
s = s.replace(old, new, 1)
c.write_text(s, encoding="utf-8")
print("MuProbe.c updated")

i = OUT / "MuProbe.inf"
t = i.read_text(encoding="utf-8")
if "ArmSmcLib" not in t:
    assert "  DevicePathLib" in t, "inf lib anchor"
    t = t.replace("  DevicePathLib", "  DevicePathLib\n  ArmSmcLib", 1)
    i.write_text(t, encoding="utf-8")
    print("MuProbe.inf updated")
else:
    print("MuProbe.inf already has ArmSmcLib")
