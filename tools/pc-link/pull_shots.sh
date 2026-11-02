#!/bin/bash
# pull the session screenshots + logs written by shot.ps1 (C:\Users\Public\rm9shot) into winboot/shots/
V=/root/.venv/bin/python3
N=<RM9_WORKDIR>/refs/ntfs_remote.py
OUT=<RM9_WORKDIR>/winboot/shots
mkdir -p $OUT; cd /root
$V $N ls rm9/session 2>&1 | tail -15
for f in launch_out.txt shots.txt shot_0.png shot_1.png shot_2.png shot_3.png shot_4.png shot_5.png; do
  rm -f $OUT/$f
  $V $N cat rm9/session/$f $OUT/$f >/dev/null 2>&1
done
ls -la $OUT
echo "--- launch_out"; tr -d '\0\r' < $OUT/launch_out.txt 2>/dev/null | head -20
echo "--- shots"; (iconv -f utf-16 -t utf-8 $OUT/shots.txt 2>/dev/null || tr -d '\0\r' < $OUT/shots.txt) | tail -5
