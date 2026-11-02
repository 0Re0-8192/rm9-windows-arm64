#!/system/bin/sh
# read-only: copy the BCD hive off the ESP into /data/local/tmp/BCD.copy
M=/data/local/tmp/espm
mkdir -p $M
umount $M 2>/dev/null
mount -t vfat -o ro,umask=000 /dev/block/by-name/esp $M || { echo MOUNT_FAILED; exit 1; }
ls -la $M/EFI/Microsoft/Boot/ | head -20
cp $M/EFI/Microsoft/Boot/BCD /data/local/tmp/BCD.copy
umount $M
ls -la /data/local/tmp/BCD.copy
