M=/data/local/tmp/espm; mkdir -p $M; umount $M 2>/dev/null
mount -t vfat -o ro,umask=000 /dev/block/by-name/esp $M || { echo MOUNT_FAILED; exit 1; }
grep -c battread $M/rm9/run.cmd; grep -n "battread" $M/rm9/run.cmd | cut -c1-140; ls -la $M/rm9/battread.ps1 | awk '{print $5}'; grep -n "refusing" $M/rm9/battread.ps1 | cut -c1-100
umount $M
