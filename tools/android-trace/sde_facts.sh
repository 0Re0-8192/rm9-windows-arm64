#!/bin/bash
F=/root/Mu-Silicium/Resources/DTBs/nx769j.dts
grep -n -E 'qcom,sde-(ctl|intf|dspp|mixer|sspp|wb|pp|merge|top|dsc|vbif|rot|inline)[a-z-]*-off|qcom,sde-(ctl|intf|mixer|sspp|pp|dsc)-(size|count)|sde-mixer-display-pref|sde-dsc|qcom,sde-intf-type|sde-has' $F | head -40 | cut -c1-200
L=$(grep -n 'qcom,sde-kms@ae00000\|qcom,sde_kms@ae00000\|qcom,mdss_mdp@ae00000\|qcom,sde' $F | head -3)
echo "$L"
S=$(grep -n -E 'qcom,sde-kms@ae00000|sde_kms@ae00000|qcom,sde_kms' $F | head -1 | cut -d: -f1)
[ -n "$S" ] && sed -n "${S},$((S+25))p" $F | cut -c1-220
