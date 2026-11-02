"""MuChain.c: write known markers into the breadcrumb page so the Sahara path can be verified:
  0xD7FF00F0 = 'MUCM' at start, 0xD7FF00F4 = 'EBS!' written inside the ExitBootServices hook."""
from pathlib import Path

p = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = p.read_text(encoding="utf-8")
if "0xD7FF00F0" not in t:
    t = t.replace('  DEBUG ((DEBUG_ERROR, "[MUCHAIN] ACPI breadcrumb area cleared\\n"));',
                  '  *(volatile UINT32 *)(UINTN)0xD7FF00F0ULL = 0x4D43554DU;   // "MUCM"\n'
                  '  DEBUG ((DEBUG_ERROR, "[MUCHAIN] ACPI breadcrumb area cleared\\n"));', 1)
    t = t.replace('  DEBUG ((DEBUG_ERROR, "[MUCHAIN] *** ExitBootServices called by the OS loader ***\\n"));',
                  '  *(volatile UINT32 *)(UINTN)0xD7FF00F4ULL = 0x21534245U;   // "EBS!"\n'
                  '  DEBUG ((DEBUG_ERROR, "[MUCHAIN] *** ExitBootServices called by the OS loader ***\\n"));', 1)
    p.write_text(t, encoding="utf-8")
print("ok", "0xD7FF00F4" in t)
