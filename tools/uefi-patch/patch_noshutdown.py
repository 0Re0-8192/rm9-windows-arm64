# -*- coding: utf-8 -*-
"""Patch Silicium BootManagerLib: UnableToBoot must warm-reset, not shutdown.
A shutdown leaves the phone as 'off + charging' => the Android charger-mode
kernel (USB 19D2:FFCC) takes over and blocks headless recovery."""
from pathlib import Path

p = Path('/root/Mu-Silicium/Silicon/Silicium/SiliciumPkg/Library/BootManagerLib/BootManager.c')
s = p.read_text(encoding='utf-8')

old = """  // Wait 10s
  gBS->Stall (10000000);

  // Shutdown
  gRT->ResetSystem (EfiResetShutdown, EFI_SUCCESS, 0, NULL);"""

new = """  // Wait 10s
  gBS->Stall (10000000);

  // [OpenCode 2026-10-12] Do not shut down here: a shutdown leaves the phone in
  // the off-mode charging kernel (USB 19D2:FFCC, empty File-CD gadget) with no
  // remote recovery path. A warm reset re-enters the normal boot chain and the
  // phone returns to Android by itself (headless-safe).
  DEBUG ((EFI_D_ERROR, "[BOOTMANAGER] no boot option; warm reset for headless recovery\\n"));
  gRT->ResetSystem (EfiResetWarm, EFI_SUCCESS, 0, NULL);"""

assert old in s, "UnableToBoot shutdown block not found"
assert "EfiResetWarm" not in s, "already patched?"
s = s.replace(old, new, 1)
p.write_text(s, encoding='utf-8')
print("BootManager.c patched: UnableToBoot -> EfiResetWarm")
