#!/system/bin/sh
# Run (as root) as soon as adb is up after a RAM boot with  trace_event=rwmmio:rwmmio_write trace_options=nooverwrite androidboot.fastboot.boottrace=enabled
# Saves the USB-related part of the whole boot-time MMIO write trace (dwc3 / phys / repeater / eud / typec / ucsi / PMIC SPMI writes) + the ioremap table + dmesg.
T=/sys/kernel/tracing
O=/data/local/tmp/bt_usb
mkdir -p $O
echo 0 > $T/tracing_on
{ echo "uptime=$(cat /proc/uptime) boot_completed=$(getprop sys.boot_completed)"; echo "buffer_size_kb=$(cat $T/buffer_size_kb)"; grep overwrite $T/trace_options; for c in $T/per_cpu/cpu*; do cat $c/stats | tr '\n' ' '; echo; done; } > $O/props.txt
grep -E 'dwc3|usb|eusb2|repeater|qmp|ssphy|hsphy|eud|ucsi|typec|spmi_pmic_arb|glink|extcon|charger|battmngr|pd_|redriver|fsa4480|ps5170' $T/trace | gzip > $O/usb_writes.txt.gz
grep ioremap /proc/vmallocinfo > $O/vmalloc_ioremap.txt
dmesg > $O/dmesg.txt
mount -t debugfs none /sys/kernel/debug 2>/dev/null
cat /sys/kernel/debug/usb/a600000.dwc3/regdump > $O/dwc3_regdump.txt 2>&1
getprop > $O/props_all.txt
cat $O/props.txt
ls -la $O
chmod -R 644 $O/*
echo DUMP_DONE
