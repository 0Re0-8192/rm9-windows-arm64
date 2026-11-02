#!/bin/bash
# usage: dts_grep2.sh <pattern> [after-lines]  - grep the nx769j DTS (WSL path) with context
grep -n -i -B3 -A${2:-10} -E "$1" /root/Mu-Silicium/Resources/DTBs/nx769j.dts | head -120
