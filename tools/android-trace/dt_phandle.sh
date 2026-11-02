cd /sys/firmware/devicetree/base
for f in $(find . -name phandle -o -name linux,phandle 2>/dev/null); do
  v=$(od -An -tx1 -v $f | tr -d ' \n')
  if [ "$v" = "00000627" ]; then echo "phandle 0x627 = $(dirname $f)"; d=$(dirname $f); for p in compatible reg label; do [ -f $d/$p ] && echo "  $p: $(tr -d '\0' < $d/$p | cut -c1-60 | tr -c '[:print:]' '.') | $(od -An -tx1 -v $d/$p | tr -d '\n' | cut -c1-60)"; done; fi
done
# the parent PMIC of that gpio controller
