# Android (root): trace every MMIO write AND read while the WLAN driver is reloaded (PCIe0 power off/on).  Output: /data/local/tmp/wifi_trace2.txt
T=/sys/kernel/tracing; [ -d $T ] || T=/sys/kernel/debug/tracing
cd $T
echo 0 > tracing_on
echo > trace
echo 65536 > buffer_size_kb 2>/dev/null
echo 1 > events/rwmmio/rwmmio_write/enable
echo 1 > events/rwmmio/rwmmio_post_read/enable
# keep only the PCIe / TCSR / GCC / CRM / pcie_sm / PARF range to keep the trace small: addresses are virtual, so filter later by module name
echo "wifi_trace: reload" 
svc wifi disable 2>/dev/null; sleep 3
echo > trace
echo 1 > tracing_on
rmmod qca_cld3_kiwi_v2 2>&1 | head -2
sleep 2
insmod /vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko 2>&1 | head -2
sleep 8
echo 0 > tracing_on
cat trace > /data/local/tmp/wifi_trace2.txt
wc -l /data/local/tmp/wifi_trace2.txt
echo 0 > events/rwmmio/rwmmio_write/enable; echo 0 > events/rwmmio/rwmmio_post_read/enable
svc wifi enable 2>/dev/null
