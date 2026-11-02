#!/system/bin/sh
D=/sys/kernel/debug/pci-msm
echo 1 > $D/rc_sel
echo 2 > $D/base_sel
echo 0x214 > $D/wr_offset
cat $D/wr_offset
echo 11 > $D/case
dmesg | grep -E 'msm_pcie_access_reg' | tail -3
echo 3 > $D/base_sel
echo 0x0 > $D/wr_offset
echo 11 > $D/case
dmesg | grep -E 'msm_pcie_access_reg' | tail -2
