# -*- coding: utf-8 -*-
"""Check from the live (root) Android kernel whether the SPMI arbiter CHNL
address that aborts in Mu is accessible there. Read-only."""
import subprocess

adb = r"C:\ADB\adb.exe"

def sh(cmd, timeout=60):
    r = subprocess.run([adb, "shell", cmd], capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace")
    return (r.stdout or "").strip(), (r.stderr or "").strip()

cmds = [
    "su -c 'ls -l /sys/class/spmi 2>/dev/null; ls /sys/bus/spmi/devices 2>/dev/null | head'",
    "su -c 'cat /proc/iomem | grep -i -A1 -B1 spmi'",
    "su -c 'which devmem; ls /system/bin | grep -i devmem; busybox | head -1'",
    # try devmem via busybox or toybox
    "su -c 'busybox devmem 0xC786008 32 2>&1 || echo NO_BUSYBOX_DEVMEM'",
    "su -c 'toybox devmem 0xC786008 32 2>&1 || echo NO_TOYBOX_DEVMEM'",
    # raw /dev/mem read fallback (4 bytes at 0xC786008)
    "su -c 'dd if=/dev/mem bs=1 skip=3350327304 count=8 2>/dev/null | od -A x -t x1z || echo DD_FAIL'",
]

for c in cmds:
    out, err = sh(c)
    print("=== ", c)
    print(out[:600])
    if err:
        print("ERR:", err[:300])
    print()
