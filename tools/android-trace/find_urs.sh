#!/bin/bash
# list the URS / USB function related driver packages in the phone's Windows DriverStore and dump the QCOM0C8B device parameters from the SYSTEM hive
V=/root/.venv/bin/python3
N=<RM9_WORKDIR>/refs/ntfs_remote.py
cd /root
$V $N ls Windows/System32/DriverStore/FileRepository 2>/dev/null | grep -iE "urs|usbfn|qcurs|dwc|synop|ucm|ucsi|usbc|typec|pmic|glink|ucx" | head -40
echo "== SYSTEM hive"
$V $N cat Windows/System32/config/SYSTEM /root/SYSTEM.cur >/dev/null 2>&1; ls -la /root/SYSTEM.cur
hivexsh /root/SYSTEM.cur <<'EOS' 2>&1 | head -60
cd \ControlSet001\Enum\ACPI\QCOM0C8B\0
ls
lsval
cd Device Parameters
lsval
EOS
