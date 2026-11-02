cd <RM9_WORKDIR>/refs/acpi/nx769j
iasl -tc -f DSDT_pcie2.dsl 2>&1 | tail -8
ls -la DSDT_pcie2.aml
cd <RM9_WORKDIR>
DSDT_FILE=DSDT_pcie2.aml DROP_ASL="Kailua/APIC.aml" EXTRA_ASL="MCFG.aml IORT.aml APIC.aml" bash refs/build_acpi.sh Mu-pcie-msi-osc > /root/var3.log 2>&1
tail -3 /root/var3.log
