#!/system/bin/sh
# Run (as root) as soon as adb is up after a RAM boot with
#   trace_event=rwmmio:rwmmio_write trace_options=nooverwrite androidboot.fastboot.boottrace=enabled
# Stops the boot-time ftrace (before init/perfetto touch it at boot_completed) and saves the first seconds
# (pci-msm probes at ~1.26 s, cnss sees the WCN at ~1.5 s) + the ioremap table to turn virtual addresses into physical ones.
T=/sys/kernel/tracing
O=/data/local/tmp/bt
mkdir -p $O
echo 0 > $T/tracing_on
# read the trace FIRST (ZTE getlog.rc atrace2_stop / perfetto may reset ftrace around boot_completed): first 4 s of the whole trace (compressed on the fly) + a small PCIe/WLAN-only extract
awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+:$/) { t = $i + 0; break } } t > 4 { exit } { print }' $T/trace | gzip > $O/trace4s.txt.gz
{
  echo "boottrace=$(getprop ro.boot.fastboot.boottrace) boot_completed=$(getprop sys.boot_completed) uptime=$(cat /proc/uptime)"
  echo "buffer_size_kb=$(cat $T/buffer_size_kb)"
  grep -E 'overwrite' $T/trace_options
  cat $T/events/rwmmio/rwmmio_write/enable
} > $O/props.txt
for c in $T/per_cpu/cpu*; do echo "== $c"; cat $c/stats; done > $O/stats.txt
grep ioremap /proc/vmallocinfo > $O/vmalloc_ioremap.txt
dmesg > $O/dmesg.txt
grep -E "qmps:|cnaop:" $T/trace > $O/kprobes.txt; cat $T/kprobe_events > $O/kprobe_events.txt
zcat $O/trace4s.txt.gz | grep -E 'pci|pcie|cnss|tcsr|PCIE' > $O/trace4s_pcie.txt
cat $O/props.txt
ls -la $O
grep -c . $O/trace4s_pcie.txt
chmod -R 644 $O/*
echo DUMP_DONE
