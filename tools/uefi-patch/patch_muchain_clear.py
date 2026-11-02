"""MuChain.c: zero the ACPI breadcrumb area (0xD7FF0000, 0x100 bytes) at start."""
from pathlib import Path

p = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = p.read_text(encoding="utf-8")
if "ACPI breadcrumb" not in t:
    anchor = '  ArmWatchdog (WDT_MS);\n'
    assert anchor in t
    t = t.replace(anchor, anchor + '\n  // ACPI breadcrumb area (see refs/acpi/instrument_dsdt.py): last 64 KB of the RAM console\n  ZeroMem ((VOID *)(UINTN)0xD7FF0000ULL, 0x100);\n  DEBUG ((DEBUG_ERROR, "[MUCHAIN] ACPI breadcrumb area cleared\\n"));\n', 1)
    p.write_text(t, encoding="utf-8")
print("ok")
