#!/bin/bash
cd /root/Mu-Silicium
grep -rn "PcdDebugPrintErrorLevel\|PcdFixedDebugPrintErrorLevel" --include='*.dsc' --include='*.inc' --include='*.dec' Platforms/ZTE/nx769jPkg Silicon/Silicium/SiliciumPkg Silicon/Qualcomm/QcomPkg 2>/dev/null | head
