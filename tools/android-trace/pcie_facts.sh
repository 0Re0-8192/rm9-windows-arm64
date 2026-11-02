#!/bin/bash
cd /root
[ -s pc.c ] || curl -sL https://raw.githubusercontent.com/torvalds/linux/master/drivers/pinctrl/qcom/pinctrl-sm8650.c -o pc.c
[ -s tc.c ] || curl -sL https://raw.githubusercontent.com/torvalds/linux/master/drivers/clk/qcom/tcsrcc-sm8650.c -o tc.c
echo "== pinctrl groups"
grep -n -E 'PINGROUP\((16|17|18|19|94|95|96),' pc.c
echo "== tcsrcc pcie0 clkref"
grep -n -B2 -A8 'tcsr_pcie_0_clkref_en = ' tc.c | head -30
grep -n -E 'reg_bits|max_register' tc.c
F=/root/Mu-Silicium/Resources/DTBs/nx769j.dts
echo "== dts tcsr nodes"
grep -n -i -E 'tcsr.*\{' $F | head
echo "== dts pcie0 pin cfg"
for n in pcie0_perst_default pcie0_clkreq_default pcie0_wake_default cnss_wlan_en_active; do
  L=$(grep -n "$n {" $F | head -1 | cut -d: -f1)
  [ -n "$L" ] && sed -n "${L},$((L+14))p" $F | tr -d '\t'
done
