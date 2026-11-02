#!/bin/bash
F=/root/Mu-Silicium/Resources/DTBs/nx769j.dts
S=$(grep -n 'qcom,cnss-kiwi@b0000000 {' $F | head -1 | cut -d: -f1)
echo "cnss-kiwi at $S"
sed -n "${S},$((S+90))p" $F | cut -c1-260
echo ---
grep -n -i -E 'rf_clk|rf-clk|clka[0-9]|"clka|ln_bb|xo_clk' $F | head -20
