cd /proc/device-tree 2>/dev/null || cd /sys/firmware/devicetree/base
for n in $(find . -maxdepth 2 -name 'gpio-keys*' 2>/dev/null); do
  echo "=== $n"
  for c in $(find $n -maxdepth 2 -type d 2>/dev/null); do
    echo "-- $c"
    for p in label linux,code gpios debounce-interval wakeup-source linux,input-type interrupts compatible; do
      [ -f $c/$p ] && echo "   $p: $(od -An -tx1 $c/$p | tr -d '\n' | cut -c1-90) | $(tr -d '\0' < $c/$p 2>/dev/null | cut -c1-40 | tr -c '[:print:]' '.')"
    done
  done
done
echo "=== pon / pwrkey"
find . -maxdepth 6 -iname '*pon*' -o -maxdepth 6 -iname '*pwrkey*' -o -maxdepth 6 -iname '*resin*' 2>/dev/null | head -12
