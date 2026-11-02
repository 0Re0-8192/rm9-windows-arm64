#!/bin/bash
# esp_rm.sh <file>...   remove files under the ESP's rm9/ directory (e.g. inttest.flag).  Mounts the ESP read-write from Android (root), syncs, unmounts.  The target phone is pinned by serial (a second phone may be attached).
export MSYS_NO_PATHCONV=1
S=<PHONE_SERIAL>
[ $# -ge 1 ] || { echo "usage: esp_rm.sh <file>..."; exit 1; }
LIST=""
for f in "$@"; do LIST="$LIST \$M/rm9/$f"; done
adb -s $S shell "su -c 'M=/data/local/tmp/espm; mkdir -p \$M; umount \$M 2>/dev/null; mount -t vfat -o rw,umask=000 /dev/block/by-name/esp \$M || { echo MOUNT_FAILED; exit 1; }; rm -f $LIST; sync; ls -la \$M/rm9 | grep -i flag; umount \$M; echo RM_DONE'"
