# -*- coding: utf-8 -*-
import subprocess
from pathlib import Path

adb = r"C:\ADB\adb.exe"
out = Path(r"<RM9_WORKDIR>\linuxboot\busybox_aarch64")
with open(out, "wb") as f:
    r = subprocess.run([adb, "exec-out", "su -c 'cat /data/adb/magisk/busybox'"],
                       stdout=f, stderr=subprocess.PIPE, timeout=300)
print("rc=", r.returncode, "size=", out.stat().st_size)
