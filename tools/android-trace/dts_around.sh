#!/bin/bash
# print N lines before a given line of the nx769j DTS (to find the PMIC parent node); usage: dts_around.sh <line> <before>
sed -n "$(( $1 - $2 )),$1p" /root/Mu-Silicium/Resources/DTBs/nx769j.dts | grep -nE "qcom,pm[0-9a-z]+@|reg = <0x[0-9a-f]+ 0x0[01]>|compatible = \"qcom,spmi-pmic\"" 
