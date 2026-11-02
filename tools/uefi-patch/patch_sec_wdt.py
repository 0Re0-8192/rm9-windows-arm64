"""Mu SEC: arm the Gunyah watchdog (~31 s) as the very first thing, so that a hang anywhere in a (re)started Mu - e.g. after Windows
rebooted the VM and left the hardware in a state ClockDxe chokes on - ends in a watchdog bite (-> dump mode -> Android) instead of a freeze.
MuChain keeps it fed (1 s timer) and only MuChain's LONGRUN mode disables it at ExitBootServices.
Idempotent; original saved as Sec.c.orig.   usage (WSL): python3 patch_sec_wdt.py [on|off]"""
import shutil
import sys
from pathlib import Path

p = Path("/root/Mu-Silicium/Silicon/Silicium/SiliciumPkg/Sec/Sec.c")
o = p.with_suffix(".c.orig")
mode = sys.argv[1] if len(sys.argv) > 1 else "on"
if not o.exists():
    shutil.copy(p, o)
t = o.read_text(encoding="utf-8")
if mode == "on":
    helper = r'''
// RM9: Gunyah watchdog (hypervisor call via SMC), armed at the very start of SEC
STATIC
VOID
RmGhWdt (UINT64 A0, UINT64 A1, UINT64 A2)
{
  register UINT64 R0 __asm__ ("x0") = A0;
  register UINT64 R1 __asm__ ("x1") = A1;
  register UINT64 R2 __asm__ ("x2") = A2;
  __asm__ volatile ("smc #0" : "+r" (R0), "+r" (R1), "+r" (R2) : : "x3", "memory");
}

STATIC
VOID
RmArmWatchdog (VOID)
{
  RmGhWdt (0x86000005ULL, 2, 0);              // GH_WDT_CONTROL: DISABLE
  RmGhWdt (0x86000008ULL, 31000, 31000);      // GH_WDT_SET_TIME (ms; hardware caps at ~32 s)
  RmGhWdt (0x86000005ULL, 3, 0);              // ENABLE
  RmGhWdt (0x86000007ULL, 0, 0);              // PING
}

VOID
SecEntry (VOID)
{
  RmArmWatchdog ();
'''
    old = "\nVOID\nSecEntry (VOID)\n{\n"
    assert old in t
    t = t.replace(old, helper, 1)
p.write_text(t, encoding="utf-8")
print("SEC watchdog:", mode)
