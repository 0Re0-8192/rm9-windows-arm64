#!/bin/bash
F=/root/Mu-Silicium/Resources/DTBs/nx769j.dts
grep -n -E 'pinctrl@|qcom,sm8650-tlmm|pineapple-pinctrl|qcom,pineapple-pinctrl' $F | head
L=$(grep -n -E 'pinctrl@f100000|pinctrl@f000000' $F | head -1 | cut -d: -f1)
[ -n "$L" ] && sed -n "${L},$((L+12))p" $F
