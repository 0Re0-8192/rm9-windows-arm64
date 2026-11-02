#!/bin/bash
# ntfs_ls.sh <path> [cat <outfile>]  list (or copy) a path on the phone's Windows partition (read-only); run inside WSL Ubuntu-24.04 as root
cd <RM9_WORKDIR>/refs
if [ "$1" = cat ]; then /root/.venv/bin/python3 ntfs_remote.py cat "$2" "$3" 2>&1 | tail -3; else /root/.venv/bin/python3 ntfs_remote.py ls "$1" 2>&1 | tail -${2:-60}; fi
