#!/bin/bash
# Enable ACPI tables for nx769j (first iteration: sister device nx729j / SM8550 "Kailua"
# tables, which already reach "Windows Boot" on the RedMagic 8 Pro) and rebuild the Mu image.
# Works on the current tree config (full-run + reserved-memory fix). Idempotent.
set -e
RM9=<RM9_WORKDIR>
ACPI=/root/Mu-Silicium/Silicium-ACPI/Platforms/ZTE
PKG=/root/Mu-Silicium/Platforms/ZTE/nx769jPkg
NAME=${1:-Mu-fullrun-acpi}

mkdir -p $ACPI/nx769j
cp $ACPI/nx729j/AcpiTables.inf $ACPI/nx769j/AcpiTables.inf
# DSDT: use ours if present (refs/acpi/nx769j/DSDT.aml), else the nx729j one
DSDT_FILE=${DSDT_FILE:-DSDT.aml}
if [ -f $RM9/refs/acpi/nx769j/$DSDT_FILE ]; then
  cp $RM9/refs/acpi/nx769j/$DSDT_FILE $ACPI/nx769j/DSDT.aml
else
  cp $ACPI/nx729j/DSDT.aml $ACPI/nx769j/DSDT.aml
fi
# tables of the Silicium INF that are replaced by our own (e.g. DROP_ASL="Kailua/APIC.aml" EXTRA_ASL="APIC.aml")
for T in ${DROP_ASL:-}; do
  sed -i "\#ASL|$T#d" $ACPI/nx769j/AcpiTables.inf
done
# extra ASL tables (e.g. EXTRA_ASL="MCFG.aml"): copied next to DSDT.aml and listed in the INF
for T in ${EXTRA_ASL:-}; do
  cp $RM9/refs/acpi/nx769j/$T $ACPI/nx769j/$T
  grep -q "ASL|$T" $ACPI/nx769j/AcpiTables.inf || sed -i "/^  ASL|DSDT.aml/a\  ASL|$T" $ACPI/nx769j/AcpiTables.inf
done
# NOTE: FILE_GUID must stay 7E374E25-8E01-4FEE-87F2-390C23C606CD (gEfiAcpiTableStorageGuid, AcpiPlatform finds the files by it)

python3 - <<'PYEOF'
from pathlib import Path
pkg = Path('/root/Mu-Silicium/Platforms/ZTE/nx769jPkg')
p = pkg / 'nx769j.dsc'
t = p.read_text(encoding='utf-8')
t = t.replace('  # TODO: create nx769j ACPI tables (Silicium-ACPI) and re-enable.\n  #\n  # nx769j/AcpiTables.inf',
              '  #\n  nx769j/AcpiTables.inf')
if '\n  nx769j/AcpiTables.inf' not in t:
    t += '\n[Components]\n  nx769j/AcpiTables.inf\n'
p.write_text(t, encoding='utf-8')
p = pkg / 'nx769j.fdf'
t = p.read_text(encoding='utf-8')
t = t.replace('  # TODO: create nx769j ACPI tables (Silicium-ACPI) and re-enable.\n  # INF RuleOverride = ACPITABLE nx769j/AcpiTables.inf',
              '  INF RuleOverride = ACPITABLE nx769j/AcpiTables.inf')
assert 'INF RuleOverride = ACPITABLE nx769j/AcpiTables.inf' in t
p.write_text(t, encoding='utf-8')
print('ACPI enabled in nx769j.dsc/fdf')
PYEOF
grep -n 'AcpiTables' $PKG/nx769j.dsc $PKG/nx769j.fdf

cd /root/Mu-Silicium
export CLANGPDB_AARCH64_PREFIX=aarch64-linux-gnu-
/root/.venv/bin/python3 build_uefi.py -d nx769j -r DEBUG > /root/acpi_build.log 2>&1 || { grep -n -E 'error:|rror -|ERROR' /root/acpi_build.log | head -20; echo BUILD FAILED; exit 1; }
tail -2 /root/acpi_build.log
mkdir -p $RM9/out
cp Mu-nx769j.img $RM9/out/$NAME.img
sha256sum $RM9/out/$NAME.img
