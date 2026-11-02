M=/data/local/tmp/espm; mkdir -p $M; umount $M 2>/dev/null
mount -t vfat -o ro,umask=000 /dev/block/by-name/esp $M || { echo MOUNT_FAILED; exit 1; }
ls -l $M/rm9/ | grep -E "run.cmd|battwatch|battlive|battprobe|battread"
echo "--- run.cmd lines 24-37:"; sed -n 24,37p $M/rm9/run.cmd | tr -d '\r' | cut -c1-130
echo "--- CR count:"; tr -cd '\r' < $M/rm9/run.cmd | wc -c
umount $M
