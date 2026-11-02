#!/bin/bash
echo "=== pcie0 node: clocks / resets / gdsc / interconnect / misc (raw)"
grep -E 'clocks =|clock-names|clock-frequency|resets =|reset-names|gdsc|vreg|qcom,aux|qcom,smmu|iommu|msi-map' /root/pcie0_node.txt | cut -c1-900
echo
echo "=== cnss-kiwi gpios (raw)"
F=/root/Mu-Silicium/Resources/DTBs/nx769j.dts
S=$(grep -n 'qcom,cnss-kiwi@b0000000 {' $F | head -1 | cut -d: -f1)
sed -n "${S},$((S+60))p" $F | grep -E 'gpio|supported-ids|rc-num|qcom,wlan' | cut -c1-200
echo
echo "=== tlmm pin config nodes for pcie0 / wlan_en"
grep -n -E 'pcie0_perst_default|pcie0_clkreq_default|pcie0_wake_default|cnss_wlan_en_active' $F | head
for n in pcie0_perst_default pcie0_clkreq_default pcie0_wake_default cnss_wlan_en_active; do
  L=$(grep -n "$n {" $F | head -1 | cut -d: -f1)
  [ -n "$L" ] && sed -n "${L},$((L+14))p" $F | tr -d '\t'
done
