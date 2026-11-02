#!/bin/bash
F=/root/Mu-Silicium/Resources/DTBs/nx769j.dts
echo "== crm nodes"
grep -n -E 'qcom,crm|crm@|clock-resource|"crm' $F | head -20
for L in $(grep -n -E 'compatible = "qcom,crm' $F | cut -d: -f1 | head -4); do
  echo "--- node near $L"; sed -n "$((L-3)),$((L+14))p" $F | cut -c1-200
done
echo "== pci-msm-drv / pcie0 crm refs"
grep -n -i -E 'crm' $F | sed -n 1,40p | cut -c1-200
