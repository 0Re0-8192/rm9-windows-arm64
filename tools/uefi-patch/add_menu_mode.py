BS = chr(92) * 2
NL = chr(10)
p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
assert 'SelfFirstByte' not in s
# prototype
proto = 'STATIC BOOLEAN SelfDeleteFile (IN CONST CHAR16 *Name);' + NL
assert proto in s
s = s.replace(proto, proto + 'STATIC INTN    SelfFirstByte (IN CONST CHAR16 *Name);' + NL, 1)
# helper before SelfDeleteFile definition comment
key = '// Deletes a file on the volume MuChain was loaded from.  TRUE only when the file existed and the delete succeeded.'
assert key in s
helper = ('// First byte of a file on the volume MuChain was loaded from, or -1 when it cannot be read.' + NL +
 'STATIC INTN' + NL +
 'SelfFirstByte (IN CONST CHAR16 *Name)' + NL +
 '{' + NL +
 '  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *Fs = NULL;' + NL +
 '  EFI_FILE_PROTOCOL               *Root = NULL, *File = NULL;' + NL +
 '  INTN                            Byte = -1;' + NL +
 '  UINT8                           B;' + NL +
 '  UINTN                           Sz = 1;' + NL + NL +
 '  if (mSelfVolume != NULL &&' + NL +
 '      !EFI_ERROR (gBS->HandleProtocol (mSelfVolume, &gEfiSimpleFileSystemProtocolGuid, (VOID **)&Fs)) &&' + NL +
 '      !EFI_ERROR (Fs->OpenVolume (Fs, &Root))) {' + NL +
 '    if (!EFI_ERROR (Root->Open (Root, &File, (CHAR16 *)Name, EFI_FILE_MODE_READ, 0))) {' + NL +
 '      if (!EFI_ERROR (File->Read (File, &Sz, &B)) && Sz == 1) {' + NL +
 '        Byte = B;' + NL +
 '      }' + NL +
 '      File->Close (File);' + NL +
 '    }' + NL +
 '    Root->Close (Root);' + NL +
 '  }' + NL +
 '  return Byte;' + NL +
 '}' + NL + NL)
s = s.replace(key, helper + key, 1)
# menu hook before ONCEMODE
a = '    if (SelfFileExists (L"' + BS + 'ONCEMODE.TXT")) {' + NL
assert a in s
menu = ('    // Boot menu (NEXT.md 0bz): MENU.TXT = Mu is always in the boot path of slot a.  NEXT.TXT = "W": start Windows this once (and put "A" back), anything else: hand over to Android (boot_b) directly.' + NL +
 '    // No file is deleted here (the FAT driver has lost neighbouring directory entries on deletes).  If the Android launch returns, reset: ABL then falls back to slot b.' + NL +
 '    if (SelfFileExists (L"' + BS + 'MENU.TXT")) {' + NL +
 '      if (SelfFirstByte (L"' + BS + 'NEXT.TXT") == (INTN)' + "'W'" + ') {' + NL +
 '        SelfWriteBytes (L"NEXT.TXT", "A", 1);' + NL +
 '        DEBUG ((DEBUG_ERROR, "[MUCHAIN] MENU: Windows requested, NEXT.TXT back to A" + chr(92) + "n"));' + NL +
 '      } else {' + NL +
 '        DEBUG ((DEBUG_ERROR, "[MUCHAIN] MENU: Android" + chr(92) + "n"));' + NL +
 '        AndroidLaunch (ImageHandle, TRUE);' + NL +
 '        gRT->ResetSystem (EfiResetCold, EFI_SUCCESS, 0, NULL);' + NL +
 '        CpuDeadLoop ();' + NL +
 '      }' + NL +
 '    }' + NL)
menu = menu.replace('" + chr(92) + "n"', chr(92) + 'n"')
s = s.replace(a, menu + a, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
