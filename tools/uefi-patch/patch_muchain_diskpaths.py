"""Patch MuChain.c: dump device path + size of every whole-disk BlockIo handle."""
from pathlib import Path

p = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = p.read_text(encoding="utf-8")
marker = "STATIC VOID\nProbeWindowsPartition (VOID)\n{"
assert marker in t
add = '''STATIC VOID
DumpDiskPaths (VOID)
{
  EFI_HANDLE *Handles = NULL;
  UINTN      Count = 0, Index;

  if (EFI_ERROR (gBS->LocateHandleBuffer (ByProtocol, &gEfiBlockIoProtocolGuid, NULL, &Count, &Handles))) {
    return;
  }
  for (Index = 0; Index < Count; Index++) {
    EFI_BLOCK_IO_PROTOCOL *B = NULL;
    if (EFI_ERROR (gBS->HandleProtocol (Handles[Index], &gEfiBlockIoProtocolGuid, (VOID **)&B)) || B == NULL || B->Media == NULL) {
      continue;
    }
    if (!B->Media->LogicalPartition) {
      CHAR16 *T = ConvertDevicePathToText (DevicePathFromHandle (Handles[Index]), FALSE, FALSE);
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] DISK handle=%p last=0x%lx bs=%u present=%u path=%s\\n",
              Handles[Index], (UINT64)B->Media->LastBlock, B->Media->BlockSize, (UINT32)B->Media->MediaPresent,
              T != NULL ? T : L"?"));
      if (T != NULL) {
        FreePool (T);
      }
    }
  }
  FreePool (Handles);
}

'''
t = t.replace(marker, add + marker)
t = t.replace("  ProbeWindowsPartition ();\n", "  DumpDiskPaths ();\n  ProbeWindowsPartition ();\n", 1)
p.write_text(t, encoding="utf-8")
print("ok")
