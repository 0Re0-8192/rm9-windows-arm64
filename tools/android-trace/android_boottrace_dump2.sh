#!/system/bin/sh
# like android_boottrace_dump.sh, plus the SMC/HVC kprobes (smc:/hvc: events from kprobe_event=... __arm_smccc_smc/hvc)
T=/sys/kernel/tracing
O=/data/local/tmp/bt
rm -rf $O; mkdir -p $O
echo 0 > $T/tracing_on
cp $T/trace $O/trace_full.txt 2>/dev/null
grep -E "qmps:|cnaop:|smc:|hvc:" $O/trace_full.txt > $O/kprobes.txt
awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+:$/) { t = $i + 0; break } } t > 4 { exit } { print }' $O/trace_full.txt | gzip > $O/trace4s.txt.gz
rm -f $O/trace_full.txt
{
  echo "boottrace=$(getprop ro.boot.fastboot.boottrace) boot_completed=$(getprop sys.boot_completed) uptime=$(cat /proc/uptime)"
  echo "buffer_size_kb=$(cat $T/buffer_size_kb)"
  grep -E 'overwrite' $T/trace_options
  cat $T/events/rwmmio/rwmmio_write/enable
} > $O/props.txt
grep ioremap /proc/vmallocinfo > $O/vmalloc_ioremap.txt
dmesg > $O/dmesg.txt
cat $T/kprobe_events > $O/kprobe_events.txt
cat $O/props.txt; wc -l $O/kprobes.txt; ls -la $O
chmod -R 644 $O/*
echo DUMP_DONE
