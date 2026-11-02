#!/bin/bash
P=<RM9_WORKDIR>/refs
V=/root/.venv/bin/python3
OUT=/root/diag_out/inv
mkdir -p $OUT
cd /root
for f in drivers.txt usb_props.txt powercfg_a.txt battery.txt acpi_keys.txt enum_acpi.txt enum_usb.txt enum_urs.txt ev_sys_errors.txt ev_pnp_config.txt; do
  rm -f $OUT/$f
  $V $P/ntfs_remote.py cat rm9/inv/$f $OUT/$f >/dev/null 2>&1
  printf '%-22s %s bytes\n' $f "$(stat -c %s $OUT/$f 2>/dev/null || echo missing)"
done
rm -f /root/diag_out/run_out.txt
$V $P/ntfs_remote.py cat rm9/run_out.txt /root/diag_out/run_out.txt >/dev/null 2>&1
echo "=========== run_out.txt (non-device part)"
iconv -f cp932 -t utf-8 -c /root/diag_out/run_out.txt | tr -d '\r\0' | grep -v '^$' | sed -n '1,400p' | grep -E "====|Name=|Model|Manufacturer|Total|MaxClock|CurrentClock|Number|Capacity|Speed|SMBIOS|Release|\[" | head -40
