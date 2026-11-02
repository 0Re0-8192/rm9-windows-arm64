#!/system/bin/sh
# keep the boot-time MMIO trace (RAM only) before it is lost: PCIe/cnss/tcsr related writes
T=/sys/kernel/tracing
echo 0 > $T/events/rwmmio/rwmmio_write/enable
grep -E 'pcie|cnss|msm_pcie|pci_msm|tcsr|clkref|qcom_pcie|pci_' $T/trace > /data/local/tmp/boottrace_pcie.txt
wc -l /data/local/tmp/boottrace_pcie.txt
wc -c $T/trace
chmod 644 /data/local/tmp/boottrace_pcie.txt
