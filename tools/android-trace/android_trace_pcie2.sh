#!/system/bin/sh
# Trace MMIO while pci-msm does a full DISABLE AND ENABLE LINK (debugfs case 3) = PHY init + PERST + link training.
T=/sys/kernel/tracing
D=/sys/kernel/debug/pci-msm
[ -d $D ] || mount -t debugfs none /sys/kernel/debug
echo 1 > $D/rc_sel
echo 0 > $T/tracing_on
echo > $T/trace
echo 32768 > $T/buffer_size_kb
echo 1 > $T/events/rwmmio/rwmmio_write/enable
echo 1 > $T/events/rwmmio/rwmmio_read/enable
echo 1 > $T/tracing_on
echo 3 > $D/case
sleep 6
echo 0 > $T/tracing_on
echo 0 > $T/events/rwmmio/rwmmio_write/enable
echo 0 > $T/events/rwmmio/rwmmio_read/enable
cp $T/trace /data/local/tmp/mmio_all2.txt
grep -c . /data/local/tmp/mmio_all2.txt
grep -E 'pci_msm_drv|msm_pcie|pcie_phy' /data/local/tmp/mmio_all2.txt > /data/local/tmp/mmio_pcie2.txt
grep -c . /data/local/tmp/mmio_pcie2.txt
dmesg | tail -30 | grep -v -E 'audit|avc' | cut -c1-200
