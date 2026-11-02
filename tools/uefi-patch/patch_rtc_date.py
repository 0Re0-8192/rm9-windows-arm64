# -*- coding: utf-8 -*-
"""Mu RealTimeClockLibNull: report the real calendar date instead of 2019-01-00.
The 3231 winload verifies the signature of boot code-integrity policies; with year 2019 / day 0 the certificates are 'not yet valid'
and the policy {60FD87F8-...} is not loaded -> STATUS_SECUREBOOT_ROLLBACK_DETECTED (0xC0430001).
usage: patch_rtc_date.py on [YYYY MM DD] | off"""
import shutil
import sys
from pathlib import Path

p = Path('/root/Mu-Silicium/Silicon/Silicium/SiliciumNullPkg/Library/RealTimeClockLibNull/RealTimeClockNull.c')
bak = p.with_suffix('.c.rm9orig')
if sys.argv[1] == 'off':
    if bak.exists():
        shutil.copyfile(bak, p)
        bak.unlink()
        print('restored')
    sys.exit(0)
y, m, d = (int(x) for x in sys.argv[2:5]) if len(sys.argv) >= 5 else (2026, 10, 20)
s = p.read_text(encoding='utf-8')
old_a = "  Time->Year  = 2019;\n  Time->Month = 1;\n"
old_b = "  Time->Day = (ElapsedSeconds / SecondsPerDay);\n"
assert old_a in s and old_b in s, 'RTC stub not in the expected form (already patched?)'
if not bak.exists():
    shutil.copyfile(p, bak)
s = s.replace(old_a, "  Time->Year  = %d;   // [rm9] real date: signed CI policies need a plausible clock\n  Time->Month = %d;\n" % (y, m), 1)
s = s.replace(old_b, "  Time->Day = %d + (ElapsedSeconds / SecondsPerDay) %% 8;\n" % d, 1)
p.write_text(s, encoding='utf-8')
print('patched: %04d-%02d-%02d (+ uptime days)' % (y, m, d))
