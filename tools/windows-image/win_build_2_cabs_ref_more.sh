cd /root/uup/files
for f in HyperV-*.cab DesktopDeployment.cab Windows11.0-KB*.cab; do d=/root/cabx/${f%.cab}; mkdir -p "$d"; cabextract -q -d "$d" "$f" 2>/dev/null || echo "FAIL $f"; done
# nested cabs/msu content
for f in Windows11.0-KB*.msu; do d=/root/cabx/${f%.msu}; mkdir -p "$d"; cabextract -q -d "$d" "$f" 2>/dev/null || echo "FAIL $f"; done
for c in $(find /root/cabx -mindepth 2 -name '*.cab' | head -50); do d="${c%.cab}_x"; mkdir -p "$d"; cabextract -q -d "$d" "$c" 2>/dev/null; done
du -sh /root/cabx; find /root/cabx -type f | wc -l
rm -f /root/cabs.wim
wimlib-imagex capture /root/cabx /root/cabs.wim cabs --no-acls 2>&1 | tr '\r' '\n' | tail -1
ls -la /root/cabs.wim