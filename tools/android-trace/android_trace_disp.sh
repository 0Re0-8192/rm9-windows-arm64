#!/system/bin/sh
# Record every MMIO access while Android turns the panel off and on again (full MDP/DSI/PHY/panel re-init), between markers.
T=/sys/kernel/tracing
echo 0 > $T/tracing_on
echo > $T/trace
echo 131072 > $T/buffer_size_kb
echo 1 > $T/events/rwmmio/rwmmio_write/enable
echo 1 > $T/events/rwmmio/rwmmio_read/enable
echo 1 > $T/tracing_on
echo "RM9_MARK_SCREEN_OFF" > $T/trace_marker
input keyevent 223
sleep 6
echo "RM9_MARK_SCREEN_ON" > $T/trace_marker
input keyevent 224
sleep 6
echo "RM9_MARK_END" > $T/trace_marker
echo 0 > $T/tracing_on
echo 0 > $T/events/rwmmio/rwmmio_write/enable
echo 0 > $T/events/rwmmio/rwmmio_read/enable
awk '/RM9_MARK_SCREEN_OFF/{p=1} p{print} /RM9_MARK_END/{exit}' $T/trace | grep -v -E 'ufs_qcom|sdhci|geni|qcom_ipc|sched_walt|arch_timer|qcom_cpufreq|llcc|bwmon|msm_kgsl|qcom_pmu|qcom_dcvs|pci_msm|cnss|qca_cld|rmnet|ipam' > /data/local/tmp/mmio_disp.txt
grep -c . /data/local/tmp/mmio_disp.txt
