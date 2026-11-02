# on the phone (root): back up the BCD / BOOTSTAT.DAT as they are now, then put the original BCD back and set BOOTSTAT.DAT aside
M=/data/local/tmp/espm; mkdir -p $M; umount $M 2>/dev/null
mount -t vfat -o rw,umask=000 /dev/block/by-name/esp $M || { echo MOUNT_FAILED; exit 1; }
B=$M/EFI/Microsoft/Boot
mkdir -p /data/local/tmp/esp_after3231
cp $B/BCD /data/local/tmp/esp_after3231/BCD
cp $B/BOOTSTAT.DAT /data/local/tmp/esp_after3231/BOOTSTAT.DAT
cp /data/local/tmp/BCD.orig $B/BCD
rm -f $B/BOOTSTAT.DAT
sync
for f in BCD BOOTSTAT.DAT; do [ -f $B/$f ] && echo "$(stat -c %s $B/$f) $f $(md5sum $B/$f | cut -c1-8)" || echo "$f removed"; done
umount $M
