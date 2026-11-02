M=/data/local/tmp/espm; mkdir -p $M; umount $M 2>/dev/null
mount -t vfat -o ro,umask=000 /dev/block/by-name/esp $M || { echo MOUNT_FAILED; exit 1; }
ls -la $M/rm9/run.cmd $M/rm9/battwatch.ps1 | awk '{print $5,$9}'
echo "--- CRLF check: lines with CR / total"; echo "$(tr -cd '\r' < $M/rm9/run.cmd | wc -c) / $(wc -l < $M/rm9/run.cmd)"
sed -n 24,36p $M/rm9/run.cmd | cat -A | cut -c1-150
umount $M
