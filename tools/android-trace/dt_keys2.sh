cd /sys/firmware/devicetree/base
for n in $(find . -name 'gpio-keys*' -type d 2>/dev/null | head -4) $(find . -name 'vol*' -type d 2>/dev/null | head -6) $(find . -path '*pon_hlos@1300/*' -type d 2>/dev/null); do
  echo "=== $n"
  for p in label linux,code gpios debounce-interval linux,input-type interrupts qcom,pull-up compatible reg status; do
    [ -f $n/$p ] && echo "   $p: $(od -An -tx1 -v $n/$p | tr -d '\n' | cut -c1-100) | $(tr -d '\0' < $n/$p 2>/dev/null | cut -c1-40 | tr -c '[:print:]' '.')"
  done
done
