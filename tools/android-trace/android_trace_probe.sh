#!/system/bin/sh
# Unload the Wi-Fi/PCIe module stack and reload pci_msm_drv under ftrace rwmmio so the probe-time setup
# (pcie_sm programming, clkref, GCC, PHY) is captured. Volatile only: a reboot restores everything.
T=/sys/kernel/tracing
M=/vendor_dlkm/lib/modules
ls $M | grep -i -E 'pci|mhi|cnss|qrtr'
svc wifi disable
sleep 2
for m in qca_cld3_kiwi_v2 cnss2 qrtr_mhi mhi_dev_satellite mhi_dev_uci mhi pci_msm_drv; do
  rmmod $m 2>&1 && echo "rmmod $m ok" || echo "rmmod $m FAILED"
done
lsmod | grep -i -E 'pci_msm|mhi|cnss'
echo 0 > $T/tracing_on
echo > $T/trace
echo 65536 > $T/buffer_size_kb
echo 1 > $T/events/rwmmio/rwmmio_write/enable
echo 1 > $T/events/rwmmio/rwmmio_read/enable
echo 1 > $T/tracing_on
echo "RM9_MARK_PROBE" > $T/trace_marker
insmod $M/pci-msm-drv.ko 2>&1 || insmod $M/pci_msm_drv.ko 2>&1
sleep 5
echo "RM9_MARK_END" > $T/trace_marker
echo 0 > $T/tracing_on
echo 0 > $T/events/rwmmio/rwmmio_write/enable
echo 0 > $T/events/rwmmio/rwmmio_read/enable
awk '/RM9_MARK_PROBE/{p=1} p{print} /RM9_MARK_END/{exit}' $T/trace | grep -E 'pci_msm_drv|pcie_pdc|crm|clk_qcom|pinctrl_msm|qcom_rpmh' > /data/local/tmp/mmio_probe.txt
grep -c . /data/local/tmp/mmio_probe.txt
dmesg | grep -E 'pci-msm|PCIe' | tail -15 | cut -c1-160
