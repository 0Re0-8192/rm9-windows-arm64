#!/system/bin/sh
# read-only: thermal zones on Android (names + current temperature) and the TSENS hardware nodes
echo "--- thermal zones"
for z in /sys/class/thermal/thermal_zone*; do
  n=$(cat $z/type 2>/dev/null); t=$(cat $z/temp 2>/dev/null)
  echo "$(basename $z) $n $t"
done | head -150
echo "--- tsens platform devices"
ls /sys/bus/platform/devices | grep -i tsens
for d in /sys/bus/platform/devices/*tsens*; do echo "== $d"; ls $d | head; done 2>/dev/null | head -40
echo "--- /dev/mem?"
ls -l /dev/mem /dev/kmem 2>&1 | head
