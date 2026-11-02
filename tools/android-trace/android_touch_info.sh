#!/system/bin/sh
# read-only: which touch controller, on which bus
echo "== input devices"
cat /proc/bus/input/devices | grep -i -E 'Name|Phys|Sysfs' | head -40
echo "== i2c/spi device names"
for d in /sys/bus/i2c/devices/* /sys/bus/spi/devices/*; do
  [ -e "$d" ] || continue
  n=$(cat $d/name 2>/dev/null); m=$(cat $d/modalias 2>/dev/null); dr=$(readlink $d/driver 2>/dev/null | sed 's#.*/##')
  echo "$d name=$n modalias=$m driver=$dr"
done
echo "== loaded touch-ish modules"
lsmod 2>/dev/null | grep -i -E 'touch|ts|goodix|fts|focal|nvt|novatek|synap|hid|himax|gt9|stm|ilitek|elan|zte' | head -20
echo "== dmesg touch"
dmesg 2>/dev/null | grep -i -E 'touch|goodix|focaltech|fts|nvt|novatek|synaptics|himax|ilitek|elan|gt9|tp_|tpd' | head -30
