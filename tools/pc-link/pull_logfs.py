import subprocess

r = subprocess.run(
    ['C:/ADB/adb.exe', '-s', '<PHONE_SERIAL>', 'exec-out', 'su', '-c',
     'dd if=/dev/block/by-name/logfs bs=1M count=8 2>/dev/null'],
    capture_output=True, timeout=180)
data = r.stdout
out = r'<RM9_WORKDIR>\backups\logfs_v9ram.bin'
open(out, 'wb').write(data)
print('saved', len(data), 'bytes to', out)
