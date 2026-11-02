#!/bin/bash
cd <RM9_WORKDIR>/refs
/root/.venv/bin/python3 ntfs_remote.py cat "$1" 2>/dev/null | head -${2:-60} | cut -c1-200
