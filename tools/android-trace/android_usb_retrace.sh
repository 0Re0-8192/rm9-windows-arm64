#!/system/bin/sh
# Re-enter USB device mode on Android (dwc3 mode none -> peripheral) while tracing every MMIO write (rwmmio ftrace), to learn the PHY / glue / repeater
# init sequence that Windows' ufxsynopsys lacks.  Runs detached: adb drops during the toggle and comes back.  Output: /data/local/tmp/usbtr/
T=/sys/kernel/tracing
O=/data/local/tmp/usbtr
M=/sys/devices/platform/soc/a600000.ssusb/mode
mkdir -p $O
echo 0 > $T/tracing_on
echo > $T/trace
echo 24000 > $T/buffer_size_kb
echo 1 > $T/events/rwmmio/rwmmio_write/enable
echo 1 > $T/events/rwmmio/rwmmio_read/enable
echo "start $(date) mode=$(cat $M)" > $O/log.txt
echo 1 > $T/tracing_on
sleep 1
echo none > $M
sleep 4
echo peripheral > $M
sleep 12
echo 0 > $T/tracing_on
echo "stop $(date) mode=$(cat $M)" >> $O/log.txt
cp $T/trace $O/trace_full.txt
grep ioremap /proc/vmallocinfo > $O/vmalloc_ioremap.txt
dmesg | tail -300 > $O/dmesg_tail.txt
echo 0 > $T/events/rwmmio/rwmmio_write/enable
echo 0 > $T/events/rwmmio/rwmmio_read/enable
echo 1408 > $T/buffer_size_kb
gzip -f $O/trace_full.txt
echo "done $(date) $(ls -la $O | wc -l)" >> $O/log.txt
