#!/system/bin/sh
# read-only dump of Android's USB device-mode state (debugfs) while the cable to the PC is connected
D=/sys/kernel/debug
O=/data/local/tmp/golden
mkdir -p $O
mountpoint -q $D || mount -t debugfs none $D
for f in $D/usb/a600000.dwc3/regdump $D/usb/a600000.dwc3/link_state $D/usb/a600000.dwc3/mode $D/usb/a600000.dwc3/testmode $D/usb/a600000.dwc3/lsp_dump $D/usb/a600000.dwc3/ep0in/state; do
  [ -e $f ] && { echo "=== $f"; cat $f 2>&1 | head -400; }
done > $O/dwc3.txt
for d in $D/88e3000.hsphy $D/a600000.ssusb "$D/c42d000.qcom,spmi:qcom,pm8550b@7:qcom,eusb2-repeater@fd00"; do
  echo "######## $d"; ls $d 2>&1
  for f in $d/*; do [ -f "$f" ] && { echo "=== $f"; cat "$f" 2>&1 | head -200; }; done
done > $O/phy_glue.txt 2>&1
cat /sys/class/udc/*/state /sys/class/udc/*/current_speed 2>&1 > $O/udc.txt
ls -la $O
