#!/bin/bash
cd /root/Mu-Silicium
grep -rn "gEfiUsbDeviceProtocolGuid\|gEfiUsbfnIoProtocolGuid" --include=*.dec --include=*.inf --include=*.dsc . 2>/dev/null | head -10
echo ---
grep -rn "UsbDeviceProtocolGuid" Silicon/Qualcomm/QcomPkg/*.dec 2>/dev/null | head -3
cat <RM9_WORKDIR>/refs/MuChain.inf 2>/dev/null | head -50
