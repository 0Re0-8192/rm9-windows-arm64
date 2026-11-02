M=/data/local/tmp/espm; mkdir -p $M; umount $M 2>/dev/null
mount -t vfat -o ro,umask=000 /dev/block/by-name/esp $M || { echo MOUNT_FAILED; exit 1; }
ls $M/rm9 | grep -i -E "launch_in_session|shot.ps1|timesync|dlog|rm9io|battread|battprobe|session.ps1" 
umount $M
