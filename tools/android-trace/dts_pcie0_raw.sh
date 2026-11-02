#!/bin/bash
# raw (unmodified) properties of the PCIe0 root complex node (qcom,pcie@1c00000) and its phy sequence
F=/root/Mu-Silicium/Resources/DTBs/nx769j.dts
S=$(grep -n 'qcom,pcie@1c00000 {' $F | head -1 | cut -d: -f1)
echo "node starts at line $S"
awk -v s=$S 'NR>=s { depth += gsub(/\{/,"{"); depth -= gsub(/\}/,"}"); if (depth==0 && NR>s) exit; print NR": "$0 }' $F > /root/pcie0_node.txt
wc -l /root/pcie0_node.txt
grep -E 'reg-names|reg = |clock-names|reset-names|supply|qcom,phy-sequence|qcom,phy-status|qcom,phy-power|qcom,pcie-phy-ver|qcom,aux-clk|perst-gpio|wake-gpio|clkreq|qcom,boot-option|qcom,slv-addr|ranges|status|gdsc|qcom,ep-latency|vreg|qcom,link|max-link|num-lanes|linux,pci-domain|qcom,use-pm' /root/pcie0_node.txt | cut -c1-1500
