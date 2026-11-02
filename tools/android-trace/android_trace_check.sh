#!/system/bin/sh
T=/sys/kernel/tracing
ls $T | head -40
echo "== events with mmio/rw"
ls $T/events 2>/dev/null | grep -i -E 'rwmmio|mmio|io'
ls $T/events/rwmmio 2>&1
echo "== available_tracers"
cat $T/available_tracers
echo "== kprobe support"
ls $T/kprobe_events $T/uprobe_events 2>&1
echo "== config"
zcat /proc/config.gz 2>/dev/null | grep -E 'TRACE_MMIO|KPROBE|FUNCTION_TRACER|DYNAMIC_FTRACE' | head
