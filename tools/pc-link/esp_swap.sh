# on the phone (root): esp_swap.sh backup|apply|restore   -- source dir /data/local/tmp/esp_new (apply) , backup dir /data/local/tmp/esp_bak
M=/data/local/tmp/espm
mkdir -p $M; umount $M 2>/dev/null
mount -t vfat -o rw,umask=000 /dev/block/by-name/esp $M || { echo MOUNT_FAILED; exit 1; }
FILES="EFI/Boot/bootaa64.efi EFI/Microsoft/Boot/bootmgfw.efi EFI/Microsoft/Boot/bootmgr.efi EFI/Microsoft/Boot/winsipolicy.p7b EFI/Microsoft/Boot/SecureBootRecovery.efi EFI/Microsoft/Boot/boot.pnd.stl EFI/Microsoft/Boot/boot.stl"
case "$1" in
 backup) rm -rf /data/local/tmp/esp_bak; for f in $FILES; do [ -f $M/$f ] && { mkdir -p /data/local/tmp/esp_bak/$(dirname $f); cp $M/$f /data/local/tmp/esp_bak/$f; }; done; find /data/local/tmp/esp_bak -type f | while read f; do echo "bak $(stat -c %s $f) $f $(md5sum $f | cut -c1-8)"; done ;;
 apply) for f in $FILES; do if [ -f /data/local/tmp/esp_new/$f ]; then cp /data/local/tmp/esp_new/$f $M/$f; fi; done; sync
        for f in $FILES; do [ -f $M/$f ] && echo "esp $(stat -c %s $M/$f) $f $(md5sum $M/$f | cut -c1-8)"; done ;;
 restore) for f in $FILES; do [ -f /data/local/tmp/esp_bak/$f ] && cp /data/local/tmp/esp_bak/$f $M/$f; done; sync
        for f in $FILES; do [ -f $M/$f ] && echo "esp $(stat -c %s $M/$f) $f $(md5sum $M/$f | cut -c1-8)"; done ;;
esac
umount $M
