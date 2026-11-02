# -*- coding: utf-8 -*-
import subprocess

adb = r"C:\ADB\adb.exe"

def sh(cmd, timeout=120):
    r = subprocess.run([adb, "shell", cmd], capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace")
    return (r.stdout or "").strip(), (r.stderr or "").strip()

out, err = sh("su -c 'which busybox; ls -l /data/adb/magisk/busybox /system/bin/busybox /system/xbin/busybox 2>/dev/null; busybox | head -2'")
print(out)
if err:
    print("ERR", err[:200])

r = subprocess.run([adb, "pull", "/data/adb/magisk/busybox", r"<RM9_WORKDIR>\linuxboot\busybox_aarch64"],
                   capture_output=True, text=True, timeout=120, encoding="utf-8", errors="replace")
print("pull magisk busybox rc=", r.returncode, r.stdout.strip()[-100:])
