# -*- coding: utf-8 -*-
"""Add a timed (delayed) halt mode to StorageCheckpointDxe + prepare_probe.py."""
from pathlib import Path

OUT = Path(r"<RM9_WORKDIR>_extra\codex_work\files-mentioned-by-the-user-01\outputs\bringup-20261012-ufs")

# ---------- 1) StorageCheckpointDxe.c ----------
c = OUT / "StorageCheckpointDxe.c"
s = c.read_text(encoding="utf-8")

old_entry = "EFI_STATUS EFIAPI\nStorageCheckpointEntry (EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable)"
assert old_entry in s, "entry function not found"

callback = """STATIC EFI_EVENT  mTimedStopEvent = NULL;

STATIC VOID EFIAPI
TimedStopCallback (EFI_EVENT Event, VOID *Context)
{
  (VOID)Event;
  (VOID)Context;
  DEBUG ((DEBUG_ERROR, "[TIMED-CHECKPOINT] timer fired; halting for RAM capture\\n"));
  StopForRamCapture ();
}

"""
s = s.replace(old_entry, callback + old_entry, 1)

old_stop = """  if (FixedPcdGetBool (PcdRamDebugStopAfterUfs)) {
    StopForRamCapture ();
  }"""
assert old_stop in s, "immediate-stop block not found"
new_stop = """  if (FixedPcdGet32 (PcdRamDebugTimedStopMs) > 0) {
    UINT32 DelayMs = FixedPcdGet32 (PcdRamDebugTimedStopMs);
    Status = gBS->CreateEvent (EVT_TIMER, TPL_CALLBACK, TimedStopCallback, NULL, &mTimedStopEvent);
    if (EFI_ERROR (Status)) {
      DEBUG ((DEBUG_ERROR, "[TIMED-CHECKPOINT] CreateEvent failed: %r\\n", Status));
    } else {
      Status = gBS->SetTimer (mTimedStopEvent, TimerRelative, (UINT64)DelayMs * 10000ULL);
      DEBUG ((DEBUG_ERROR, "[TIMED-CHECKPOINT] armed: %lu ms status=%r (BDS will run until the timer fires)\\n", (UINT64)DelayMs, Status));
    }
  } else if (FixedPcdGetBool (PcdRamDebugStopAfterUfs)) {
    StopForRamCapture ();
  }"""
s = s.replace(old_stop, new_stop, 1)
c.write_text(s, encoding="utf-8")
print("StorageCheckpointDxe.c patched")

# ---------- 2) StorageCheckpointDxe.inf ----------
i = OUT / "StorageCheckpointDxe.inf"
t = i.read_text(encoding="utf-8")
old_pcd = "  gNx769jDebugTokenSpaceGuid.PcdRamDebugStopAfterUfs"
assert old_pcd in t, "inf pcd not found"
t = t.replace(old_pcd, old_pcd + "\n  gNx769jDebugTokenSpaceGuid.PcdRamDebugTimedStopMs", 1)
i.write_text(t, encoding="utf-8")
print("StorageCheckpointDxe.inf patched")

# ---------- 3) prepare_probe.py ----------
p = OUT / "prepare_probe.py"
q = p.read_text(encoding="utf-8")

old_arg = "parser.add_argument('--stop-at', default='UFSDxe/UFSDxe.inf', help='[OpenCode] APRIORI anchor line for the StorageCheckpointDxe insertion (default: UFSDxe)')"
assert old_arg in q, "stop-at arg not found"
q = q.replace(old_arg,
    old_arg + "\nparser.add_argument('--timed-stop-ms', type=int, default=0, help='[OpenCode] Arm a delayed halt (ms) at the checkpoint slot instead of halting immediately; use together with --stop-after-ufs')",
    1)

old_dec = "  gNx769jDebugTokenSpaceGuid.PcdRamDebugStopAfterUfs|FALSE|BOOLEAN|0x00000004"
assert old_dec in q, "dec template pcd not found"
q = q.replace(old_dec,
    old_dec + "\n  gNx769jDebugTokenSpaceGuid.PcdRamDebugTimedStopMs|0|UINT32|0x00000005",
    1)

old_dsc = "  gNx769jDebugTokenSpaceGuid.PcdRamDebugStopAfterUfs|{'TRUE' if args.stop_after_ufs else 'FALSE'}"
assert old_dsc in q, "dsc template pcd not found"
q = q.replace(old_dsc,
    old_dsc + "\n  gNx769jDebugTokenSpaceGuid.PcdRamDebugTimedStopMs|{args.timed_stop_ms}",
    1)

p.write_text(q, encoding="utf-8")
import ast
ast.parse(q)
print("prepare_probe.py patched (syntax OK)")
