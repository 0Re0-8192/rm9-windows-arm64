#!/bin/bash
# esp_fetch.sh <outdir> <file>...   wait until Android is back, then copy files from the ESP's rm9/ directory (mounted read-only) to <outdir>.
# Reads straight from the block device through adb exec-out (no copy left in /data/local/tmp, so no stale files); an empty/missing file is reported as size 0.
export MSYS_NO_PATHCONV=1
S=<PHONE_SERIAL>
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  b=$(adb -s $S shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  [ "$b" = 1 ] && break
  sleep 20
done
echo "boot_completed=$b"
OUT=$1; shift
mkdir -p "$OUT"
for f in "$@"; do
  adb -s $S exec-out "su -c 'M=/data/local/tmp/espm; mkdir -p \$M; umount \$M 2>/dev/null; mount -t vfat -o ro,umask=000 /dev/block/by-name/esp \$M && cat \$M/rm9/$f; umount \$M'" > "$OUT/$f" 2>/dev/null
  echo "$f $(stat -c %s "$OUT/$f")"
done
