M=/data/local/tmp/espm; mkdir -p $M; umount $M 2>/dev/null
mount -t vfat -o ro,umask=000 /dev/block/by-name/esp $M || { echo MOUNT_FAILED; exit 1; }
for f in EFI/Microsoft/Boot/BCD EFI/Microsoft/Boot/BOOTSTAT.DAT EFI/Microsoft/Boot/BCD.LOG1 EFI/Microsoft/Boot/BCD.LOG2 rm9/run.cmd; do [ -f $M/$f ] && echo "$(stat -c '%s %y' $M/$f | cut -c1-30) $f $(md5sum $M/$f | cut -c1-8)"; done
ls $M/rm9 2>/dev/null | head
umount $M
