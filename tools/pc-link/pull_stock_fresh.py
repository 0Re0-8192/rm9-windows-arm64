import hashlib
import subprocess
from pathlib import Path

OUT = Path(r'<RM9_WORKDIR>\backups')
ADB = 'C:/ADB/adb.exe'
SERIAL = '<PHONE_SERIAL>'

# fresh stock reads via root adb
def pull(part, outname, size):
    r = subprocess.run(
        [ADB, '-s', SERIAL, 'exec-out', 'su', '-c',
         f'dd if=/dev/block/by-name/{part} bs=4096 count={size // 4096} 2>/dev/null'],
        capture_output=True, timeout=300)
    data = r.stdout
    p = OUT / outname
    p.write_bytes(data)
    print(f'{part}: {len(data)} bytes -> {outname} sha256={hashlib.sha256(data).hexdigest()[:16]}')
    return data

cur_init = pull('init_boot_b', 'init_boot_b_fresh.img', 8388608)
cur_vbmeta = pull('vbmeta_b', 'vbmeta_b_fresh.img', 65536)

old_init = Path(r'<RM9_WORKDIR>\dumps\init_boot_b.img').read_bytes()
old_vbmeta = Path(r'<RM9_WORKDIR>\dumps\vbmeta_b.img').read_bytes()
print('init_boot_b matches dump:', hashlib.sha256(cur_init).hexdigest() == hashlib.sha256(old_init).hexdigest())
print('vbmeta_b matches dump:  ', hashlib.sha256(cur_vbmeta).hexdigest() == hashlib.sha256(old_vbmeta).hexdigest())
