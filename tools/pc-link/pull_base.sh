#!/bin/bash
cd /root
rm -f /root/win_base.img
/root/.venv/bin/python3 <RM9_WORKDIR>/refs/pull_windows_fast.py /root/win_base.img 8 > /root/pull.log 2>&1
echo EXIT $? >> /root/pull.log
