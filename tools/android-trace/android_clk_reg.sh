#!/system/bin/sh
[ -d /sys/kernel/debug/clk ] || mount -t debugfs none /sys/kernel/debug
echo "== clk_summary pcie_0"
grep -i -E 'pcie_0|pcie0|clkref_en|cnoc_pcie|aggre_noc_pcie|ddrss_pcie|rf_clk|clka1|clk_src' /sys/kernel/debug/clk/clk_summary 2>&1 | grep -i -E 'pcie_0|pcie0|pcie_clkref|cnoc_pcie|aggre_noc_pcie|ddrss_pcie|clka|rf_clk' | head -40
echo "== regulator_summary"
cat /sys/kernel/debug/regulator/regulator_summary 2>&1 | grep -i -E 'regulator +use|^ *(s[0-9]+[a-z]|l[0-9]+[a-z]|ldo|smp|pcie|wlan|pmu|vreg)' | head -150
