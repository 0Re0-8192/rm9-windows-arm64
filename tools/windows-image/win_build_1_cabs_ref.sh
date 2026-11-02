cd /root/uup/files
rm -rf /root/cabx /root/cabs.wim; mkdir -p /root/cabx
for f in Microsoft-*.cab OpenSSH-*.cab; do d=/root/cabx/${f%.cab}; mkdir -p "$d"; cabextract -q -d "$d" "$f" || echo "FAIL $f"; done
du -sh /root/cabx; ls /root/cabx | wc -l
find /root/cabx -type f | wc -l
wimlib-imagex capture /root/cabx /root/cabs.wim "cabs" --no-acls 2>&1 | tail -2
ls -la /root/cabs.wim
H=0x883507ee52e9c68ff8b4e3458b730b41e6026a72
wimlib-imagex dir /root/cabs.wim 1 --detailed 2>/dev/null | grep -c $H