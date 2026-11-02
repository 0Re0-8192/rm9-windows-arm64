#!/bin/bash
# inspect usbfn / ufx / urs related keys in the phone's SYSTEM hive (read-only, fresh pull)
/root/.venv/bin/python3 <RM9_WORKDIR>/refs/ntfs_remote.py cat Windows/System32/config/SYSTEM /root/SYSTEM.cur >/dev/null 2>&1
H=/root/SYSTEM.cur
for p in 'ufx01000' 'ufxsynopsys' 'genericusbfn' 'urscx01000' 'UrsSynopsys' 'QcUsbFnSSFilter' 'usbfnbase'; do
  echo "=== Services\$p"
  printf 'cd \ControlSet001\Services\%s\nls\nlsval\n' "$p" > /root/hv.cmd
  hivexsh $H < /root/hv.cmd 2>&1 | cut -c1-160 | head -30
done
echo "=== Services names matching usb/fn/ufx/urs/ucm"
printf 'cd \ControlSet001\Services\nls\n' > /root/hv.cmd
hivexsh $H < /root/hv.cmd 2>&1 | grep -iE "usb|fn|ufx|urs|ucm|ucsi|qcusb|pmic|glink" | head -50
echo "=== Control\usbfn?"
printf 'cd \ControlSet001\Control\nls\n' > /root/hv.cmd
hivexsh $H < /root/hv.cmd 2>&1 | grep -iE "usb|fn" | head
