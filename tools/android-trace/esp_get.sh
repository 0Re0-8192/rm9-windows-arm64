# esp_get.sh <path inside ESP> <out file>: copy one file out of the ESP (read-only mount); run as root.
M=/data/local/tmp/espm
mkdir -p $M
umount $M 2>/dev/null
mount -t vfat -o ro,umask=000 /dev/block/by-name/esp $M || { echo MOUNT_FAILED; exit 1; }
cp "$M/$1" "$2" && chmod 644 "$2"
ls -la "$M/$1"
umount $M
