# -*- coding: utf-8 -*-
"""Rewrite TimedStopCallback: log the GH watchdog re-arm results, then force a
data abort so XBL's crash collector (19D2:0112 dump mode) engages even when the
watchdog path misbehaves during the BDS phase."""
from pathlib import Path

OUT = Path(r"<RM9_WORKDIR>_extra\codex_work\files-mentioned-by-the-user-01\outputs\bringup-20261012-ufs")
c = OUT / "StorageCheckpointDxe.c"
s = c.read_text(encoding="utf-8")

old = """STATIC EFI_EVENT  mTimedStopEvent = NULL;

STATIC VOID EFIAPI
TimedStopCallback (EFI_EVENT Event, VOID *Context)
{
  (VOID)Event;
  (VOID)Context;
  DEBUG ((DEBUG_ERROR, "[TIMED-CHECKPOINT] timer fired; halting for RAM capture\\n"));
  StopForRamCapture ();
}"""

new = """STATIC EFI_EVENT  mTimedStopEvent = NULL;

STATIC VOID EFIAPI
TimedStopCallback (EFI_EVENT Event, VOID *Context)
{
  INT64 CallStatus;
  (VOID)Event;
  (VOID)Context;
  DEBUG ((DEBUG_ERROR, "[TIMED-CHECKPOINT] timer fired; re-arm results follow, then a forced abort\\n"));
  CallStatus = WatchdogCall (GH_WDT_CONTROL, 2, 0);
  DEBUG ((DEBUG_ERROR, "[TIMED-CHECKPOINT] DISABLE ret=%ld\\n", CallStatus));
  if (CallStatus == 0) {
    CallStatus = WatchdogCall (GH_WDT_SET_TIME, 30000, 30000);
    DEBUG ((DEBUG_ERROR, "[TIMED-CHECKPOINT] SET_TIME ret=%ld\\n", CallStatus));
  }
  if (CallStatus == 0) {
    CallStatus = WatchdogCall (GH_WDT_CONTROL, 3, 0);
    DEBUG ((DEBUG_ERROR, "[TIMED-CHECKPOINT] ENABLE ret=%ld\\n", CallStatus));
  }
  if (CallStatus == 0) {
    CallStatus = WatchdogCall (GH_WDT_PING, 0, 0);
    DEBUG ((DEBUG_ERROR, "[TIMED-CHECKPOINT] PING ret=%ld\\n", CallStatus));
  }
  DEBUG ((DEBUG_ERROR, "[TIMED-CHECKPOINT] forcing data abort for crash capture (watchdog ret=%ld)\\n", CallStatus));
  *(volatile UINTN *)0x100 = 0xDEADBEEF;
  CpuDeadLoop ();
}"""

assert old in s, "old callback not found"
s = s.replace(old, new, 1)
c.write_text(s, encoding="utf-8")
print("TimedStopCallback replaced (crash variant)")
