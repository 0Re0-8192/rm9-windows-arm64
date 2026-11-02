#!/system/bin/sh
# read-only: UFS flags / write-protect info visible from Android sysfs
D=$(ls -d /sys/devices/platform/soc/*.ufshc 2>/dev/null | head -1)
[ -z "$D" ] && D=$(dirname $(ls /sys/devices/platform/*/*/flags/power_on_wpe 2>/dev/null | head -1) 2>/dev/null)
echo "ufshc dir: $D"
for f in $D/flags/*; do echo "flag $(basename $f) = $(cat $f 2>/dev/null)"; done
for n in 0 1 2 3 4 5; do
  p=$(ls -d $D/*/target*/*:0:0:$n 2>/dev/null | head -1)
  echo "lun$n path: $p"
done
echo "--- unit descriptors (write protect)"
ls $D/unit_descriptor 2>/dev/null | head
for f in $D/unit_descriptor/*; do echo "$f"; ls $f 2>/dev/null | head -3; done 2>/dev/null | head -20
find $D -maxdepth 2 -name 'lu_write_protect' 2>/dev/null | while read f; do echo "$f = $(cat $f)"; done
