"""MuChain: DumpMemMap - print the whole UEFI memory map (type, start, pages, attr) once, early (diagnostics)."""
from pathlib import Path

c = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = c.read_text(encoding="utf-8")
assert "DumpMemMap" not in t
fn = r'''
STATIC VOID
DumpMemMap (VOID)
{
  UINTN                  Size = 0, Key, DSz;
  UINT32                 DVer;
  EFI_MEMORY_DESCRIPTOR  *Map = NULL, *D;
  UINTN                  N, K;
  UINT64                 High = 0;

  gBS->GetMemoryMap (&Size, NULL, &Key, &DSz, &DVer);
  Size += 8 * DSz;
  Map = AllocatePool (Size);
  if (Map == NULL || EFI_ERROR (gBS->GetMemoryMap (&Size, Map, &Key, &DSz, &DVer))) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] MEMMAP: GetMemoryMap failed\n"));
    return;
  }
  N = Size / DSz;
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] MEMMAP: %lu descriptors\n", (UINT64)N));
  for (K = 0; K < N; K++) {
    D = (EFI_MEMORY_DESCRIPTOR *)((UINT8 *)Map + K * DSz);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] MEMMAP t=%02u 0x%010lx pages=0x%lx attr=0x%lx\n", D->Type, D->PhysicalStart, D->NumberOfPages, D->Attribute));
    if (D->PhysicalStart + D->NumberOfPages * 4096 > High) {
      High = D->PhysicalStart + D->NumberOfPages * 4096;
    }
  }
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] MEMMAP: highest end 0x%lx\n", High));
  FreePool (Map);
}
'''
t = t.replace("\nSTATIC VOID\nUfsProbe (VOID)", fn + "\nSTATIC VOID\nUfsProbe (VOID)", 1)
old = "STATIC VOID\nUfsProbe (VOID)\n{\n"
assert old in t
t = t.replace(old, old + "  DumpMemMap ();\n", 1)
c.write_text(t, encoding="utf-8")
print("ok")
