#!/bin/bash
mkdir -p /mnt/w2
umount /mnt/w2 2>/dev/null
mount -t ntfs-3g -o loop,ro /root/win_golden3_gui_ok.img /mnt/w2 || exit 1
cd /mnt/w2/Windows/WinSxS
echo "== msix/appx/appxbundle under WinSxS (any version)"
find . -maxdepth 3 -type f \( -iname "*.msix" -o -iname "*.appx" -o -iname "*.msixbundle" -o -iname "*.appxbundle" \) 2>/dev/null | head -40
echo "== package-like dirs in WinSxS"
ls | grep -i -E "client-cbs|client-core|clientcore|appx" | head -30
echo "== Windows\SystemApps\MicrosoftWindows.Client.CBS sample"
ls /mnt/w2/Windows/SystemApps/MicrosoftWindows.Client.CBS_cw5n1h2txyewy | head -12
umount /mnt/w2
