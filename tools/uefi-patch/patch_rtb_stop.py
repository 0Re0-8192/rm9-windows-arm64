# -*- coding: utf-8 -*-
"""Add a ReadyToBoot-hook stop mode (deterministic BDS-phase capture) to
StorageCheckpointDxe + prepare_probe.py.
The ReadyToBoot event is signalled synchronously right before the first boot
attempt (UefiBootManagerLib BmBoot), so the notify fires even if timer events
are broken."""
from pathlib import Path

OUT = Path(r"<RM9_WORKDIR>_extra\codex_work\files-mentioned-by-the-user-01\outputs\bringup-20261012-ufs")

# ---------- 1) StorageCheckpointDxe.c ----------
c = OUT / "StorageCheckpointDxe.c"
s = c.read_text(encoding="utf-8")

# include UefiLib
old_inc = "#include <Library/UefiBootServicesTableLib.h>"
assert old_inc in s, "include anchor not found"
s = s.replace(old_inc, old_inc + "\n#include <Library/UefiLib.h>", 1)

# add RTB callback right before StorageCheckpointEntry
old_entry = "EFI_STATUS EFIAPI\nStorageCheckpointEntry (EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable)"
assert old_entry in s, "entry not found"
rtb = """STATIC VOID EFIAPI
RtbStopCallback (EFI_EVENT Event, VOID *Context)
{
  INT64 CallStatus;
  (VOID)Event;
  (VOID)Context;
  DEBUG ((DEBUG_ERROR, "[RTB-CHECKPOINT] ReadyToBoot reached; re-arm results follow, then a forced abort\\n"));
  CallStatus = WatchdogCall (GH_WDT_CONTROL, 2, 0);
  DEBUG ((DEBUG_ERROR, "[RTB-CHECKPOINT] DISABLE ret=%ld\\n", CallStatus));
  if (CallStatus == 0) {
    CallStatus = WatchdogCall (GH_WDT_SET_TIME, 30000, 30000);
    DEBUG ((DEBUG_ERROR, "[RTB-CHECKPOINT] SET_TIME ret=%ld\\n", CallStatus));
  }
  if (CallStatus == 0) {
    CallStatus = WatchdogCall (GH_WDT_CONTROL, 3, 0);
    DEBUG ((DEBUG_ERROR, "[RTB-CHECKPOINT] ENABLE ret=%ld\\n", CallStatus));
  }
  if (CallStatus == 0) {
    CallStatus = WatchdogCall (GH_WDT_PING, 0, 0);
    DEBUG ((DEBUG_ERROR, "[RTB-CHECKPOINT] PING ret=%ld\\n", CallStatus));
  }
  DEBUG ((DEBUG_ERROR, "[RTB-CHECKPOINT] forcing data abort for crash capture (watchdog ret=%ld)\\n", CallStatus));
  *(volatile UINTN *)0x100 = 0xDEADBEEF;
  CpuDeadLoop ();
}

"""
s = s.replace(old_entry, rtb + old_entry, 1)

# entry branch: timed -> rtb -> immediate
old_branch = """  } else if (FixedPcdGetBool (PcdRamDebugStopAfterUfs)) {
    StopForRamCapture ();
  }"""
assert old_branch in s, "stop branch not found"
new_branch = """  } else if (FixedPcdGetBool (PcdRamDebugReadyToBootStop)) {
    EFI_EVENT RtbEvent = NULL;
    Status = EfiCreateEventReadyToBootEx (TPL_CALLBACK, RtbStopCallback, NULL, &RtbEvent);
    DEBUG ((DEBUG_ERROR, "[RTB-CHECKPOINT] armed status=%r\\n", Status));
  } else if (FixedPcdGetBool (PcdRamDebugStopAfterUfs)) {
    StopForRamCapture ();
  }"""
s = s.replace(old_branch, new_branch, 1)
c.write_text(s, encoding="utf-8")
print("StorageCheckpointDxe.c: RTB mode added")

# ---------- 2) .inf ----------
i = OUT / "StorageCheckpointDxe.inf"
t = i.read_text(encoding="utf-8")
old_pcd = "  gNx769jDebugTokenSpaceGuid.PcdRamDebugTimedStopMs"
assert old_pcd in t, "inf pcd anchor not found"
t = t.replace(old_pcd, old_pcd + "\n  gNx769jDebugTokenSpaceGuid.PcdRamDebugReadyToBootStop", 1)
old_lib = "  UefiDriverEntryPoint"
assert old_lib in t, "inf lib anchor not found"
t = t.replace(old_lib, "  UefiDriverEntryPoint\n  UefiLib", 1)
i.write_text(t, encoding="utf-8")
print("StorageCheckpointDxe.inf: PCD + UefiLib added")

# ---------- 3) prepare_probe.py ----------
p = OUT / "prepare_probe.py"
q = p.read_text(encoding="utf-8")
old_arg = "parser.add_argument('--timed-stop-ms', type=int, default=0, help='[OpenCode] Arm a delayed halt (ms) at the checkpoint slot instead of halting immediately; use together with --stop-after-ufs')"
assert old_arg in q, "timed arg not found"
q = q.replace(old_arg,
    old_arg + "\nparser.add_argument('--rtb-stop', action='store_true', help='[OpenCode] Stop on the ReadyToBoot event (right before the first boot attempt); use together with --stop-after-ufs')",
    1)
old_dec = "  gNx769jDebugTokenSpaceGuid.PcdRamDebugTimedStopMs|0|UINT32|0x00000005"
assert old_dec in q, "dec template not found"
q = q.replace(old_dec,
    old_dec + "\n  gNx769jDebugTokenSpaceGuid.PcdRamDebugReadyToBootStop|FALSE|BOOLEAN|0x00000006",
    1)
old_dsc = "  gNx769jDebugTokenSpaceGuid.PcdRamDebugTimedStopMs|{args.timed_stop_ms}"
assert old_dsc in q, "dsc template not found"
q = q.replace(old_dsc,
    old_dsc + "\n  gNx769jDebugTokenSpaceGuid.PcdRamDebugReadyToBootStop|{'TRUE' if args.rtb_stop else 'FALSE'}",
    1)
p.write_text(q, encoding="utf-8")
import ast
ast.parse(q)
print("prepare_probe.py: --rtb-stop added (syntax OK)")
