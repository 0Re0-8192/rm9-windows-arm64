"""FrameBufferSerialPortLib::SerialPortWrite also feeds the Gunyah watchdog (GH_WDT_PING via SMC), rate-limited to ~every 100 ms by the generic counter.
Reason: the RamDebugGuard 1 s EFI timer never fires during DXE on this Mu (no timer ticks delivered), so nothing fed the 31 s SEC-armed watchdog until
MuChain loaded.  DXE prints constantly, so a stuck-silent hang still ends in a bite, but a long slow init does not.   Idempotent."""
from pathlib import Path

p = Path("/root/Mu-Silicium/Silicon/Silicium/SiliciumPkg/Library/FrameBufferSerialPortLib/FrameBufferSerialPortLib.c")
t = p.read_text(encoding="utf-8")
if "RM9_SERIALPET" in t:
    print("already patched")
    raise SystemExit(0)
helper = r'''
// RM9_SERIALPET: feed the Gunyah watchdog from the debug-print path (rate limited)
STATIC VOID
Rm9PetFromSerial (VOID)
{
  UINT64 Cnt, Freq;
  STATIC UINT64 Last = 0;

  __asm__ volatile ("mrs %0, cntpct_el0" : "=r" (Cnt));
  __asm__ volatile ("mrs %0, cntfrq_el0" : "=r" (Freq));
  if (Last != 0 && (Cnt - Last) < (Freq / 10)) {
    return;
  }
  Last = Cnt;
  {
    register UINT64 R0 __asm__ ("x0") = 0x86000007ULL;   // GH_WDT_PING
    register UINT64 R1 __asm__ ("x1") = 0;
    register UINT64 R2 __asm__ ("x2") = 0;
    __asm__ volatile ("smc #0" : "+r" (R0), "+r" (R1), "+r" (R2) : : "x3", "memory");
  }
}

'''
anchor = "UINTN\nEFIAPI\nSerialPortWrite ("
assert anchor in t
t = t.replace(anchor, helper + anchor, 1)
old = "  // Get Frame Buffer Memory\n  Status = GetFrameBufferMemory (&FbBase, &FbLength);\n  if (EFI_ERROR (Status)) {\n    return 0;\n  }\n"
assert old in t
t = t.replace(old, old + "\n  Rm9PetFromSerial ();\n", 1)
p.write_text(t, encoding="utf-8")
print("patched")
