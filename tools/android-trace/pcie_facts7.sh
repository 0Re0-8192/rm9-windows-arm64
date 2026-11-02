#!/bin/bash
F=/root/Mu-Silicium/Resources/DTBs/nx769j.dts
echo "== sleep clk / 32k / suspend clk"
grep -n -i -E 'sleep_clk|sleep-clk|clk_32k|32k|susclk|wlan_sleep|xo_sleep|clk-out|clock-out' $F | head -30
echo "== pmk8550 gpio nodes (names)"
L=$(grep -n 'qcom,pmk8550@0 {' $F | cut -d: -f1)
sed -n "${L},$((L+80))p" $F | grep -n -E 'gpio|clk|pinctrl' | head -20
echo "== wlan related pin/gpio names in dts"
grep -n -i -E 'wlan|wcn|sw_ctrl|wifi' $F | grep -v -E 'qcom,vdd-wlan|cnss-kiwi|supported-ids' | head -40 | cut -c1-200
