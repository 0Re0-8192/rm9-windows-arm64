# -*- coding: utf-8 -*-
"""Patch MsBootOptionsLib: register the MassStorage app as a last-resort boot
option so the headless install flow (UFS exposed over USB to the PC) works
without any keypad input."""
from pathlib import Path

p = Path('/root/Mu-Silicium/Silicon/Silicium/SiliciumPkg/Library/MsBootOptionsLib/MsBootOptionsLib.c')
s = p.read_text(encoding='utf-8')

old = '  RegisterFvBootOption (FixedPcdGetPtr (PcdUfpLoaderFile), L"FFU Mode",         (UINTN)-1, LOAD_OPTION_HIDDEN, NULL, 0);'
assert old in s, "FFU register line not found"
assert 'MassStorageAppGuid' not in s, "already patched?"

new = old + """

  // [OpenCode 2026-10-12] Headless install flow: when no OS is present, the
  // MassStorage app becomes the last-resort boot option and exposes the UFS
  // over USB to the PC automatically (no keypad input required).
  {
    EFI_GUID MassStorageAppGuid = { 0xFB14ECD8, 0x9432, 0x48B8, { 0xA6, 0x92, 0xAE, 0x4B, 0xC1, 0x9D, 0x56, 0x8B } };
    RegisterFvBootOption (&MassStorageAppGuid, L"Mass Storage", (UINTN)-1, LOAD_OPTION_ACTIVE, NULL, 0);
  }"""

s = s.replace(old, new, 1)
p.write_text(s, encoding='utf-8')
print("MsBootOptionsLib.c patched: Mass Storage last-resort boot option added")
