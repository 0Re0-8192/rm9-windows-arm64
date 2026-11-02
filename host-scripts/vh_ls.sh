cd <RM9_WORKDIR>/refs
P=/root/.venv/bin/python3
for d in "$@"; do echo "--- $d"; $P vhdx_ntfs_remote.py ls "$d" 2>&1 | tail -40; done
