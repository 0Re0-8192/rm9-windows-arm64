#!/bin/bash
# does the BCD on the ESP image look like a *system store* to Windows?
set -e
mkdir -p /mnt/e
umount /mnt/e 2>/dev/null || true
for img in /root/esp_v3.img /root/esp_v4.img; do
  mount -o ro,loop $img /mnt/e
  echo "=== $img"
  B=/mnt/e/EFI/Microsoft/Boot/BCD
  ls -la $B
  hivexsh $B <<'EOF'
cd \Description
lsval
EOF
  umount /mnt/e
done
