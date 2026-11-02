#!/bin/bash
# stop QEMU, mount the Windows partition read-only (force, the volume is dirty) and show the Setup error logs
pkill -x qemu-system-aar 2>/dev/null || true
sleep 3
WIN_LBA=$((2048 + 131072))
OFF=$((WIN_LBA * 4096))
mkdir -p /mnt/qw
umount /mnt/qw 2>/dev/null || true
mount -t ntfs-3g -o ro,loop,offset=$OFF,force,norecover /root/qemu/disk.img /mnt/qw
P=/mnt/qw/Windows/Panther
echo "--- Panther"; ls -la $P | head -30
for f in setuperr.log; do
  for d in $P /mnt/qw/Windows/System32/Sysprep/Panther; do
    [ -f $d/$f ] && { echo "=== $d/$f"; tail -n 40 $d/$f | tr -d '\r'; }
  done
done
echo "=== setupact.log: last error/fail lines"
for d in $P /mnt/qw/Windows/System32/Sysprep/Panther; do
  [ -f $d/setupact.log ] && { echo "--- $d/setupact.log ($(wc -l < $d/setupact.log) lines)"; grep -i -E "error|fail|0x[0-9a-f]{8}" $d/setupact.log | tail -n 25 | tr -d '\r'; }
done
cp -r $P /root/panther_v5 2>/dev/null || true
cp -r /mnt/qw/Windows/System32/Sysprep/Panther /root/panther_v5_sysprep 2>/dev/null || true
umount /mnt/qw
