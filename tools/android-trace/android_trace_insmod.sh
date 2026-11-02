#!/system/bin/sh
T=/sys/kernel/tracing
M=/vendor_dlkm/lib/modules
lsmod | grep -E 'pci_msm|pcie_pdc|mhi'
echo 0 > $T/tracing_on
echo > $T/trace
echo 65536 > $T/buffer_size_kb
echo 1 > $T/events/rwmmio/rwmmio_write/enable
echo 1 > $T/events/rwmmio/rwmmio_read/enable
echo 1 > $T/tracing_on
echo "RM9_MARK_PROBE" > $T/trace_marker
insmod $M/pci-msm-drv.ko 2>&1
sleep 5
echo "RM9_MARK_END" > $T/trace_marker
echo 0 > $T/tracing_on
echo 0 > $T/events/rwmmio/rwmmio_write/enable
echo 0 > $T/events/rwmmio/rwmmio_read/enable
awk '/RM9_MARK_PROBE/{p=1} p{print} /RM9_MARK_END/{exit}' $T/trace | grep -v -E 'ufs_qcom|sdhci|geni|qcom_ipc|sched_walt|arch_timer|qcom_cpufreq|llcc|bwmon|msm_kgsl|msm_drm|qcom_pmu|qcom_dcvs' > /data/local/tmp/mmio_probe.txt
grep -c . /data/local/tmp/mmio_probe.txt
dmesg | grep -E 'pci-msm|PCIe|msm_pcie|already' | tail -12 | cut -c1-170
