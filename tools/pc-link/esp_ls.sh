M=/data/local/tmp/espm
mkdir -p $M; umount $M 2>/dev/null
mount -t vfat -o ro,umask=000 /dev/block/by-name/esp $M || { echo MOUNT_FAILED; exit 1; }
cd $M
find . -type f | while read f; do echo "$(stat -c '%s %y' "$f" | cut -c1-30) $f $(md5sum "$f" | cut -c1-8)"; done | head -80
cd /; umount $M
