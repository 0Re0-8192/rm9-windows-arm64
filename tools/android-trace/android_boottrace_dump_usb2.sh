#!/system/bin/sh
# Like android_boottrace_dump_usb.sh but keeps EVERY rwmmio write in a window around the first USB PHY power-on (clocks/resets/GDSC writes by the clk/reset drivers included)
T=/sys/kernel/tracing
O=/data/local/tmp/bt_usb2
mkdir -p $O
echo 0 > $T/tracing_on
{ echo "uptime=$(cat /proc/uptime)"; echo "buffer_size_kb=$(cat $T/buffer_size_kb)"; } > $O/props.txt
T0=$(grep -m1 'msm_eusb2_phy_power' $T/trace | sed -n 's/.* \([0-9]*\.[0-9]*\): rwmmio_write.*/\1/p')
echo "T0=$T0" >> $O/props.txt
awk -v t0="$T0" '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+\.[0-9]+:$/) { t = $i + 0; break } } t >= t0 - 3.0 && t <= t0 + 3.0 { print }' $T/trace | gzip > $O/win.txt.gz
grep ioremap /proc/vmallocinfo > $O/vmalloc_ioremap.txt
dmesg > $O/dmesg.txt
cat $O/props.txt
ls -la $O
chmod -R 644 $O/*
echo DUMP_DONE
