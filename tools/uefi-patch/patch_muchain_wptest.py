"""MuChain: UfsWpTest() - only when \\WPTEST.TXT exists on MuChain's own volume (logdump, LUN4) and NOBOOT.TXT is set.
  1. write \\WPPRE.TXT (must succeed)  2. SET_FLAG fPowerOnWPEn  3. READ_FLAG (expect 1)  4. write \\WPPOST.TXT (expect failure)"""
from pathlib import Path

c = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = c.read_text(encoding="utf-8")
assert "UfsWpTest" not in t

fn = r'''
STATIC EFI_STATUS
WriteTestFile (IN CONST CHAR16 *Name, IN CONST CHAR8 *Text)
{
  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *Fs = NULL;
  EFI_FILE_PROTOCOL               *Root = NULL, *File = NULL;
  EFI_STATUS                      S, S2 = EFI_SUCCESS, S3;
  UINTN                           Len = AsciiStrLen (Text);

  if (mSelfVolume == NULL ||
      EFI_ERROR (gBS->HandleProtocol (mSelfVolume, &gEfiSimpleFileSystemProtocolGuid, (VOID **)&Fs)) ||
      EFI_ERROR (Fs->OpenVolume (Fs, &Root))) {
    return EFI_NOT_FOUND;
  }
  S = Root->Open (Root, &File, (CHAR16 *)Name, EFI_FILE_MODE_READ | EFI_FILE_MODE_WRITE | EFI_FILE_MODE_CREATE, 0);
  if (!EFI_ERROR (S)) {
    S  = File->Write (File, &Len, (VOID *)Text);
    S2 = File->Flush (File);
    File->Close (File);
  }
  S3 = Root->Flush (Root);
  Root->Close (Root);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] WPTEST write %s: write=%r flush=%r volflush=%r\n", Name, S, S2, S3));
  if (EFI_ERROR (S)) { return S; }
  if (EFI_ERROR (S2)) { return S2; }
  return S3;
}

STATIC VOID
UfsWpTest (IN UINT64 Base)
{
  UINT8      V, R;
  EFI_STATUS Q;

  DEBUG ((DEBUG_ERROR, "[MUCHAIN] WPTEST begin\n"));
  Q = WriteTestFile (L"\\WPPRE.TXT", "before set_flag\n");
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] WPTEST pre-write result: %r (expect Success)\n", Q));
  if (EFI_ERROR (Q)) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] WPTEST abort: cannot even write before the flag\n"));
    return;
  }
  Q = UfsQueryFlag (Base, 6, 3, &V, &R);       // SET_FLAG fPowerOnWPEn
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] WPTEST SET_FLAG fPowerOnWPEn: %r flag=%u qresp=0x%x\n", Q, V, R));
  Q = UfsQueryFlag (Base, 5, 3, &V, &R);       // READ_FLAG
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] WPTEST READ_FLAG fPowerOnWPEn: %r flag=%u qresp=0x%x (expect flag=1)\n", Q, V, R));
  Q = WriteTestFile (L"\\WPPOST.TXT", "after set_flag\n");
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] WPTEST post-write result: %r (expect an error if LUN4 is protected)\n", Q));
}
'''
t = t.replace("\nSTATIC VOID\nUfsProbe (VOID)", fn + "\nSTATIC VOID\nUfsProbe (VOID)", 1)
# SelfFileExists is defined later than UfsProbe; forward-declare it
t = t.replace("\nSTATIC VOID\nUfsProbe (VOID)", "\nSTATIC BOOLEAN SelfFileExists (IN CONST CHAR16 *Name);\n\nSTATIC VOID\nUfsProbe (VOID)", 1)
old = "  UfsProbeOne (0x1D90000ULL, 0x1000,  FALSE);   // UFS ICE area, descriptor only\n"
assert old in t
t = t.replace(old, old + "  if (SelfFileExists (L\"\\\\WPTEST.TXT\") && SelfFileExists (L\"\\\\NOBOOT.TXT\")) {\n    UfsWpTest (0x1D84000ULL);\n  }\n", 1)
c.write_text(t, encoding="utf-8")

# make_logdump_img / build_muchain: third arg 'wptest'
m = Path(r"<RM9_WORKDIR>\refs\make_logdump_img.sh")
s = m.read_text(encoding="utf-8")
if "wptest" not in s:
    s = s.replace('if [ "$2" = noboot ]; then echo 1 > /mnt/m/NOBOOT.TXT; fi',
                  'if [ "$2" = noboot ]; then echo 1 > /mnt/m/NOBOOT.TXT; fi\nif [ "$3" = wptest ]; then echo 1 > /mnt/m/WPTEST.TXT; fi', 1)
    m.write_text(s, encoding="utf-8", newline="\n")
b = Path(r"<RM9_WORKDIR>\refs\build_muchain.sh")
s = b.read_text(encoding="utf-8")
s = s.replace('bash $RM9/refs/make_logdump_img.sh "$1" "$2"', 'bash $RM9/refs/make_logdump_img.sh "$1" "$2" "$3"')
b.write_text(s, encoding="utf-8", newline="\n")
print("ok")
