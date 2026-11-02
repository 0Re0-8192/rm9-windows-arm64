#!/system/bin/sh
# read-only: where is the APPS watchdog on this SoC?
echo "--- platform devices"
ls /sys/bus/platform/devices | grep -i -E 'wdt|watchdog'
for d in /sys/bus/platform/devices/*wdt* /sys/bus/platform/devices/*watchdog*; do
  [ -e "$d" ] || continue
  echo "== $d"; ls "$d" | head -20
done
echo "--- device tree"
for n in $(find /proc/device-tree -maxdepth 3 -iname '*wdt*' -o -maxdepth 3 -iname '*watchdog*' 2>/dev/null); do
  echo "== $n"
  [ -f "$n/reg" ] && xxd "$n/reg" | head -2
  [ -f "$n/compatible" ] && cat "$n/compatible" && echo
  [ -f "$n/qcom,bark-time" ] && xxd "$n/qcom,bark-time"
  [ -f "$n/qcom,pet-time" ] && xxd "$n/qcom,pet-time"
  [ -f "$n/qcom,bite-time" ] && xxd "$n/qcom,bite-time"
done
echo "--- /sys/class/watchdog"
ls /sys/class/watchdog 2>/dev/null
cat /sys/class/watchdog/watchdog0/timeout /sys/class/watchdog/watchdog0/identity 2>/dev/null
