#!/system/bin/sh
# Dump ONE pci-msm register space of PCIe0 (arg: base_sel 1=parf 2=phy 3=dm_core 4=elbi 5=iatu 6=conf 7=pcie_sm 9=tcsr).
# 2026-10-15: dumping 1,2,3,4,5,7,9 back-to-back hung the whole SoC -> run ONE base per call, in the order parf, phy, dm_core, and keep the
# Wi-Fi link up (screen on / wlan enabled) so the PCIe clocks are not gated.
D=/sys/kernel/debug/pci-msm
B=$1
[ -n "$B" ] || { echo "usage: $0 <base_sel>"; exit 1; }
[ -d $D ] || mount -t debugfs none /sys/kernel/debug
echo 1 > $D/rc_sel
echo $B > $D/base_sel
sync
echo 13 > $D/case
sleep 1
dmesg | tail -400 > /data/local/tmp/pcie_dump_$B.txt
wc -l /data/local/tmp/pcie_dump_$B.txt
