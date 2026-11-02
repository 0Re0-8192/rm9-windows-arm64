#!/system/bin/sh
# Record every MMIO write/read (ftrace rwmmio) while Android re-initialises the PCIe0 link via a Wi-Fi off/on cycle,
# then keep only the lines whose caller is the pci-msm driver (msm_pcie / pcie_phy / clk / reset helpers it calls).
T=/sys/kernel/tracing
echo 0 > $T/tracing_on
echo > $T/trace
echo 16384 > $T/buffer_size_kb
echo 1 > $T/events/rwmmio/rwmmio_write/enable
echo 1 > $T/events/rwmmio/rwmmio_read/enable
echo 1 > $T/tracing_on
svc wifi disable
sleep 4
svc wifi enable
sleep 8
echo 0 > $T/tracing_on
echo 0 > $T/events/rwmmio/rwmmio_write/enable
echo 0 > $T/events/rwmmio/rwmmio_read/enable
cp $T/trace /data/local/tmp/mmio_all.txt
grep -c . /data/local/tmp/mmio_all.txt
grep -E 'pcie|pci_msm|phy' /data/local/tmp/mmio_all.txt > /data/local/tmp/mmio_pcie.txt
grep -c . /data/local/tmp/mmio_pcie.txt
