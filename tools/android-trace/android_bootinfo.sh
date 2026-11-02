#!/system/bin/sh
cat /sys/kernel/tracing/events/rwmmio/rwmmio_write/format
echo "== cmdline"
cat /proc/cmdline
echo "== partitions"
ls -la /dev/block/by-name | grep -E ' boot|vendor_boot|init_boot'
getprop ro.boot.slot_suffix
echo "== trace size"
cat /sys/kernel/tracing/buffer_size_kb
