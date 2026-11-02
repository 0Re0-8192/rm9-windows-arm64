"""MuChain.c: (1) \\NOBOOT.TXT on the logdump FAT = diagnostics only, never start bootmgfw (safe mode);
(2) list every protocol GUID installed on each whole-disk BlockIo handle and on handles that expose
    UFS-ish protocols (to see whether the Qualcomm UFS driver offers query/pass-thru interfaces)."""
from pathlib import Path

p = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = p.read_text(encoding="utf-8")

if "DumpProtocolsOnDisks" not in t:
    func = '''
STATIC VOID
DumpProtocolsOnDisks (VOID)
{
  EFI_HANDLE *Handles = NULL;
  UINTN      Count = 0, Index;

  if (EFI_ERROR (gBS->LocateHandleBuffer (ByProtocol, &gEfiBlockIoProtocolGuid, NULL, &Count, &Handles))) {
    return;
  }
  for (Index = 0; Index < Count; Index++) {
    EFI_BLOCK_IO_PROTOCOL *B = NULL;
    EFI_GUID              **Guids = NULL;
    UINTN                 N = 0, K;

    if (EFI_ERROR (gBS->HandleProtocol (Handles[Index], &gEfiBlockIoProtocolGuid, (VOID **)&B)) || B == NULL ||
        B->Media == NULL || B->Media->LogicalPartition) {
      continue;
    }
    if (!EFI_ERROR (gBS->ProtocolsPerHandle (Handles[Index], &Guids, &N)) && Guids != NULL) {
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] disk handle %p (last=0x%lx) has %lu protocols:\\n", Handles[Index], (UINT64)B->Media->LastBlock, (UINT64)N));
      for (K = 0; K < N; K++) {
        DEBUG ((DEBUG_ERROR, "[MUCHAIN]    proto %g\\n", Guids[K]));
      }
      FreePool (Guids);
    }
  }
  FreePool (Handles);

  // handles carrying the standard EDK2 UFS interfaces?
  {
    STATIC EFI_GUID UfsPassThru   = { 0x1d3de7f0, 0x0807, 0x424f, { 0xaa, 0x69, 0x11, 0xa5, 0x4e, 0x19, 0xa4, 0x6f } };
    STATIC EFI_GUID UfsDevConfig  = { 0xb30dfeed, 0x947f, 0x4396, { 0xb1, 0x5a, 0xdf, 0xbd, 0xb9, 0x16, 0xdc, 0x24 } };
    STATIC EFI_GUID UfsHc         = { 0xebd3a5d9, 0x1b59, 0x4f10, { 0x84, 0x4a, 0x9c, 0x5c, 0x6b, 0x8a, 0x4c, 0x90 } };
    VOID *Pt = NULL;
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] UfsPassThru: %r  UfsDeviceConfig: %r  (UfsHc guess: %r)\\n",
            gBS->LocateProtocol (&UfsPassThru, NULL, &Pt), gBS->LocateProtocol (&UfsDevConfig, NULL, &Pt),
            gBS->LocateProtocol (&UfsHc, NULL, &Pt)));
  }
}

STATIC BOOLEAN
SelfFileExists (IN CONST CHAR16 *Name)
{
  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *Fs = NULL;
  EFI_FILE_PROTOCOL               *Root = NULL, *File = NULL;
  BOOLEAN                         Found = FALSE;

  if (mSelfVolume != NULL &&
      !EFI_ERROR (gBS->HandleProtocol (mSelfVolume, &gEfiSimpleFileSystemProtocolGuid, (VOID **)&Fs)) &&
      !EFI_ERROR (Fs->OpenVolume (Fs, &Root))) {
    if (!EFI_ERROR (Root->Open (Root, &File, (CHAR16 *)Name, EFI_FILE_MODE_READ, 0))) {
      File->Close (File);
      Found = TRUE;
    }
    Root->Close (Root);
  }
  return Found;
}

'''
    t = t.replace("STATIC EFI_STATUS\nFindBootMgr (", func + "STATIC EFI_STATUS\nFindBootMgr (", 1)

# call sites: after volume known (right after the snapshot-timer block) and before StartImage
if "NOBOOT.TXT" not in t:
    anchor = "  DumpConfigTables ();\n  PatchBreakpoints (NewImage);"
    assert anchor in t
    t = t.replace(anchor,
                  "  DumpProtocolsOnDisks ();\n"
                  "  if (SelfFileExists (L\"\\\\NOBOOT.TXT\")) {\n"
                  "    DEBUG ((DEBUG_ERROR, \"[MUCHAIN] NOBOOT.TXT present: diagnostics only, NOT starting bootmgfw\\n\"));\n"
                  "    CpuDeadLoop ();\n"
                  "    return EFI_SUCCESS;\n"
                  "  }\n" + anchor, 1)
p.write_text(t, encoding="utf-8")
print("ok", "NOBOOT.TXT" in t, "DumpProtocolsOnDisks" in t)
