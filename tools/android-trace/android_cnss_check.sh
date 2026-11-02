#!/system/bin/sh
[ -d /sys/kernel/debug/cnss ] || mount -t debugfs none /sys/kernel/debug
ls -la /sys/kernel/debug/cnss
echo "== dev_boot"
cat /sys/kernel/debug/cnss/dev_boot 2>&1 | head -30
echo "== stats"
cat /sys/kernel/debug/cnss/stats 2>&1 | head -20
