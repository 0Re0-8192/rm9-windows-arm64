#!/system/bin/sh
# Full PCIe0 + WCN power cycle on Android: unload / reload the WLAN driver (cnss powers the chip off and on, full PHY init + PERST + link training)
# with ftrace rwmmio recording everything between two markers.
T=/sys/kernel/tracing
svc wifi disable
sleep 3
echo 0 > $T/tracing_on
echo > $T/trace
echo 65536 > $T/buffer_size_kb
echo 1 > $T/events/rwmmio/rwmmio_write/enable
echo 1 > $T/events/rwmmio/rwmmio_read/enable
echo 1 > $T/tracing_on
echo "RM9_MARK_RMMOD" > $T/trace_marker
rmmod qca_cld3_kiwi_v2 2>&1
sleep 3
echo "RM9_MARK_INSMOD" > $T/trace_marker
insmod /vendor_dlkm/lib/modules/qca_cld3_kiwi_v2.ko 2>&1
sleep 6
echo "RM9_MARK_END" > $T/trace_marker
echo 0 > $T/tracing_on
echo 0 > $T/events/rwmmio/rwmmio_write/enable
echo 0 > $T/events/rwmmio/rwmmio_read/enable
awk '/RM9_MARK_RMMOD/{p=1} p{print} /RM9_MARK_END/{exit}' $T/trace | grep -v -E 'ufs_qcom|sdhci|geni|qcom_ipc|sched_walt|arch_timer' > /data/local/tmp/mmio_win.txt
grep -c . /data/local/tmp/mmio_win.txt
svc wifi enable
dmesg | grep -E 'msm_pcie_(enable|disable)|PHY is ready|link initialized|insmod|rmmod' | cut -c1-140 | tail -12
