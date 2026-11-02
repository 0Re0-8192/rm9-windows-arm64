#!/system/bin/sh
# install_run_wrapper.sh <wrapper file>: put the wrapper in as ESP rm9/run.cmd; the previous run.cmd is kept once as rm9/run_prod.cmd (run as root)
W=$1
M=/data/local/tmp/espm
mkdir -p $M
umount $M 2>/dev/null
mount -t vfat -o rw,umask=000 /dev/block/by-name/esp $M || { echo MOUNT_FAILED; exit 1; }
[ -f $M/rm9/run_prod.cmd ] || cp $M/rm9/run.cmd $M/rm9/run_prod.cmd
cp "$W" $M/rm9/run.cmd
sync
ls -la $M/rm9/run.cmd $M/rm9/run_prod.cmd
umount $M
