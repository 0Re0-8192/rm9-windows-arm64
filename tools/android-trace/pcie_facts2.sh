#!/bin/bash
F=/root/Mu-Silicium/Resources/DTBs/nx769j.dts
grep -n -i -E 'sm8650-tcsr|1fc0000|1fd5000|tcsrcc|tcsr-clk|tcsr_' $F | head -20
echo ---
grep -n -i -E 'clkref' $F | head -10
