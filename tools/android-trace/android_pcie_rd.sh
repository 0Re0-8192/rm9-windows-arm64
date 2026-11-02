#!/system/bin/sh
# usage: android_pcie_rd.sh <base_sel> <start_hex> <end_hex>   (reads one dword at a time through pci-msm debugfs case 11)
D=/sys/kernel/debug/pci-msm
B=$1; S=$(($2)); E=$(($3))
echo 1 > $D/rc_sel
echo $B > $D/base_sel
OUT=/data/local/tmp/pcie_rd_$B.txt
: > $OUT
O=$S
while [ $O -le $E ]; do
  printf "0x%x" $O > $D/wr_offset
  echo 11 > $D/case
  O=$((O+4))
done
dmesg | grep -E 'PCIe.*(0x[0-9a-fA-F]+)' | grep -v -E 'audit|avc' | tail -$(( (E-S)/4 + 40 )) > $OUT
wc -l $OUT
head -3 $OUT
