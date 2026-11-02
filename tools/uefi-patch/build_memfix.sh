#!/bin/bash
# Rebuild the verified "full-run diag" Mu config (same recipe as build_diag.sh)
# plus the reserved-memory fix. Does NOT overwrite the original Mu-fullrun-diag.img.
set -e
OUT='<RM9_WORKDIR>_extra/codex_work/files-mentioned-by-the-user-01/outputs/bringup-20261012-ufs'
RM9='<RM9_WORKDIR>'
PKG=/root/Mu-Silicium/Platforms/ZTE/nx769jPkg

cd "$OUT"
echo "=== PREPARE (full-run config) ==="
python3 prepare_probe.py --mode guard --order dal --quarantine-ipcc --spmi-owner-probe --stock-order --ufs-wake --omit-pmic --stop-after-ufs --stop-at 'NubiaBoardDxe' --timed-stop-ms 8000 >/dev/null

mkdir -p "$PKG/Applications/MuProbe" "$PKG/Applications/MuChain" "$PKG/Drivers/MuDiagDxe"
cp "$OUT/MuProbe.c"   "$PKG/Applications/MuProbe/MuProbe.c"
cp "$OUT/MuProbe.inf" "$PKG/Applications/MuProbe/MuProbe.inf"
cp "$OUT/MuDiagDxe.c"   "$PKG/Drivers/MuDiagDxe/MuDiagDxe.c"
cp "$OUT/MuDiagDxe.inf" "$PKG/Drivers/MuDiagDxe/MuDiagDxe.inf"
cp "$RM9/refs/MuChain.c"   "$PKG/Applications/MuChain/MuChain.c"
cp "$RM9/refs/MuChain.inf" "$PKG/Applications/MuChain/MuChain.inf"

python3 - <<'PYEOF'
from pathlib import Path
pkg = Path('/root/Mu-Silicium/Platforms/ZTE/nx769jPkg')
for f in ['Include/DXE.inc', 'Include/APRIORI.inc']:
    p = pkg / f
    out = []
    for ln in p.read_text(encoding='utf-8').splitlines(keepends=True):
        if ('UsbMsdDxe' in ln or 'UsbDeviceDxe' in ln) and not ln.lstrip().startswith('#'):
            out.append('# ' + ln)
        else:
            out.append(ln)
    p.write_text(''.join(out), encoding='utf-8')
p = pkg / 'Include/APRIORI.inc'
lines = p.read_text(encoding='utf-8').splitlines(keepends=True)
if not any('MuDiagDxe' in l for l in lines):
    idx = next(i for i, l in enumerate(lines) if 'StorageCheckpointDxe' in l)
    lines[idx:idx] = ['  INF nx769jPkg/Drivers/MuDiagDxe/MuDiagDxe.inf\n']
    p.write_text(''.join(lines), encoding='utf-8')
p = pkg / 'Include/DXE.inc'
t = p.read_text(encoding='utf-8')
if 'MuDiagDxe' not in t:
    t += '\n  INF nx769jPkg/Drivers/MuDiagDxe/MuDiagDxe.inf\n'
if 'MuProbe' not in t:
    t += '\n  INF nx769jPkg/Applications/MuProbe/MuProbe.inf\n'
p.write_text(t, encoding='utf-8')
p = pkg / 'nx769j.dsc'
t = p.read_text(encoding='utf-8')
if 'MuDiagDxe' not in t:
    t += '\n[Components]\n  nx769jPkg/Drivers/MuDiagDxe/MuDiagDxe.inf\n'
if 'MuProbe' not in t:
    t += '\n[Components]\n  nx769jPkg/Applications/MuProbe/MuProbe.inf\n'
if 'MuChain' not in t:
    t += '\n[Components]\n  nx769jPkg/Applications/MuChain/MuChain.inf\n'
p.write_text(t, encoding='utf-8')
print('config done')
PYEOF

python3 "$RM9/refs/patch_memmap_reserved.py"

cd /root/Mu-Silicium
export CLANGPDB_AARCH64_PREFIX=aarch64-linux-gnu-
echo "=== BUILD ==="
/root/.venv/bin/python3 build_uefi.py -d nx769j -r DEBUG 2>&1 | tail -3

mkdir -p "$RM9/out"
cp Mu-nx769j.img "$RM9/out/Mu-fullrun-memfix.img"
sha256sum "$RM9/out/Mu-fullrun-memfix.img"
cp Build/nx769jPkg/DEBUG_CLANGPDB/AARCH64/MuChain.efi "$RM9/out/MuChain.efi"
sha256sum "$RM9/out/MuChain.efi"
echo "=== DONE ==="
