#!/bin/bash
cd /root
[ -s dispcc.c ] || curl -sL 'https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/clk/qcom/dispcc-sm8550.c' -o dispcc.c
ls -la dispcc.c
echo "== dispcc clocks (halt/enable)"
grep -n -E '^static struct clk_branch|halt_reg|enable_reg = |\.gdscr|\.cmd_rcgr|disp_cc_mdss_(mdp|ahb|vsync|byte0|pclk0|esc0|rot)' dispcc.c | head -120
echo "== gcc disp clocks"
grep -n -E 'static struct clk_branch gcc_disp_(ahb|hf_axi|sf_axi)_clk' -A8 gcc-sm8650.c | grep -E 'halt_reg|enable_reg|enable_mask|clk_branch'
echo "== regmap max / base in sm8650.dtsi"
grep -n -B2 -A6 'dispcc: clock-controller' sm8650.dtsi | head -30
