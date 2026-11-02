#!/system/bin/sh
getprop sys.boot_completed
grep -o 'trace_event=[^ ]*' /proc/cmdline
grep -o 'trace_buf_size=[^ ]*' /proc/cmdline
cat /sys/kernel/tracing/events/rwmmio/rwmmio_write/enable
