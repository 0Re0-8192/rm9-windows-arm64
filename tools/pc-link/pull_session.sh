#!/bin/bash
# pull C:\rm9\session\*.txt (written by session.ps1) and print head/tail of each
V=/root/.venv/bin/python3
cd /root
for f in users changes temps alive shots; do
  rm -f /root/s_$f.txt
  $V <RM9_WORKDIR>/refs/ntfs_remote.py cat rm9/session/$f.txt /root/s_$f.txt >/dev/null 2>&1
  echo "=== $f ($(stat -c %s /root/s_$f.txt 2>/dev/null || echo missing) bytes)"
  if [ -f /root/s_$f.txt ]; then
    if head -c 2 /root/s_$f.txt | xxd -p | grep -q '^fffe'; then iconv -f utf-16 -t utf-8 /root/s_$f.txt | tr -d '\r' > /root/s_$f.u8; else tr -d '\r\0' < /root/s_$f.txt > /root/s_$f.u8; fi
    head -${HEADN:-30} /root/s_$f.u8; echo ...; tail -${TAILN:-6} /root/s_$f.u8
  fi
done
