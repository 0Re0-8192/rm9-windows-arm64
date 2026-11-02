# -*- coding: utf-8 -*-
"""Mu ArmPsciResetSystemLib: EfiResetShutdown -> PSCI SYSTEM_RESET (cold reset).
usage: patch_shutdown_to_reset.py on|off   (off restores the .rm9orig backup)
A shutdown leaves the phone in off-mode charging (USB 19D2:FFCC); a reset returns to Android by itself."""
import shutil, sys
from pathlib import Path
p = Path('/root/Mu-Silicium/Mu_Basecore/ArmPkg/Library/ArmPsciResetSystemLib/ArmPsciResetSystemLib.c')
bak = p.with_suffix('.c.rm9orig')
if sys.argv[1] == 'off':
    if bak.exists():
        shutil.copyfile(bak, p); bak.unlink(); print('restored')
    else:
        print('nothing to restore')
    sys.exit(0)
s = p.read_text(encoding='utf-8')
old = """  // Send a PSCI 0.2 SYSTEM_RESET command
  Args.Arg0 = ARM_SMC_ID_PSCI_SYSTEM_OFF;
"""
new = """  // [rm9] shutdown -> SYSTEM_RESET so the phone returns to Android instead of off-mode charging
  Args.Arg0 = ARM_SMC_ID_PSCI_SYSTEM_RESET;
"""
assert old in s, 'ResetShutdown block not found'
if not bak.exists():
    shutil.copyfile(p, bak)
p.write_text(s.replace(old, new, 1), encoding='utf-8')
print('patched: ResetShutdown -> SYSTEM_RESET')
