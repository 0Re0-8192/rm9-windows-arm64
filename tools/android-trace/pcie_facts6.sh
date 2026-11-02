#!/bin/bash
F=/root/Mu-Silicium/Resources/DTBs/nx769j.dts
echo "== spmi pmic nodes"
grep -n -E 'qcom,pm[a-z0-9]+@[0-9a-f]+ \{|qcom,pmk[0-9a-z]+@[0-9a-f]+ \{|qcom,pmr[0-9a-z]+@[0-9a-f]+ \{' $F | head -30
echo "== rpmh-regulators nodes (compatible + qcom,pmic-id)"
grep -n -E 'rpmh-regulators|qcom,pmic-id' $F | head -40
