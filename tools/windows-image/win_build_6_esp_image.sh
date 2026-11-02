set -e
W=<RM9_WORKDIR>/winboot
rm -f /root/esp.img
truncate -s 536870912 /root/esp.img
mkfs.vfat -F 32 -S 4096 -s 1 -n ESP /root/esp.img | tail -3
mkdir -p /mnt/e && mount -o loop /root/esp.img /mnt/e
cp -r $W/esp_template/EFI /mnt/e/
cp $W/BCD_patched /mnt/e/EFI/Microsoft/Boot/BCD
sync
find /mnt/e -type f | wc -l; du -sh /mnt/e; ls -la /mnt/e/EFI/Boot /mnt/e/EFI/Microsoft/Boot/BCD
fsck.vfat -n /root/esp.img | tail -2
umount /mnt/e
cmp <(head -c 3 /root/esp.img | xxd -p) <(echo ebfe90) || true
xxd -l 64 /root/esp.img | head -4