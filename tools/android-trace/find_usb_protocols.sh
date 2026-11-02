#!/bin/bash
cd /root/Mu-Silicium
grep -rIl -i "UsbConfigProtocol\|EFIUsbConfig\|QcomUsbConfig\|UsbPwrCtrl\|EFI_USB_CONFIG" --include=*.h --include=*.dec --include=*.inf --include=*.c . 2>/dev/null | head -20
echo "== headers named like usb in QcomPkg/Include"
find . -ipath "*Include*" -iname "*usb*" 2>/dev/null | head -20
echo "== GUIDs in dec"
grep -rn -i "UsbConfig\|UsbPwrCtrl\|UsbInit\|UsbFn" --include=*.dec . 2>/dev/null | head -20
