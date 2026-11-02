#!/system/bin/sh
# dump PCIe0 register spaces of the LIVE (link-up) Android configuration through the pci-msm debugfs
D=/sys/kernel/debug/pci-msm
echo 1 > $D/rc_sel
OUT=/data/local/tmp/pcie_dump.txt
: > $OUT
for B in 1 2 3 4 5 7 9; do
  echo $B > $D/base_sel
  dmesg -c > /dev/null 2>&1
  echo 13 > $D/case
  sleep 1
  echo "##### base_sel=$B" >> $OUT
  dmesg >> $OUT 2>&1
done
echo 0 > $D/case
echo 16 > $D/case
dmesg | tail -20 >> $OUT
wc -l $OUT
