#!/system/bin/sh
mount | grep -E 'debugfs|tracefs' | head -3
[ -d /sys/kernel/debug/pci-msm ] || mount -t debugfs none /sys/kernel/debug 2>&1
ls /sys/kernel/debug/ 2>&1 | head -50
echo "== pci-msm"
ls -la /sys/kernel/debug/pci-msm 2>&1
for f in /sys/kernel/debug/pci-msm/*; do echo "-- $f"; head -c 600 $f 2>&1; done 2>&1 | head -120
