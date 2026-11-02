#!/bin/bash
F=/root/Mu-Silicium/Resources/DTBs/nx769j.dts
sed -n 22548,22640p $F | cut -c1-420
echo ======= phandle targets
for p in 0x2e 0x2f 0x4d 0x55; do
  L=$(grep -n "phandle = <$p>;" $F | head -1 | cut -d: -f1)
  echo "phandle $p at line $L"
  [ -n "$L" ] && sed -n "$((L-12)),$((L))p" $F | grep -E 'compatible|reg =|\{' | tail -4
done
