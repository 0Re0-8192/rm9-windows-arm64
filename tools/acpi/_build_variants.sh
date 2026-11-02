#!/bin/bash
cd <RM9_WORKDIR>
DSDT_FILE=DSDT_pcie.aml EXTRA_ASL="MCFG.aml IORT.aml" bash refs/build_acpi.sh Mu-pcie-iort > /root/var1.log 2>&1
DSDT_FILE=DSDT_pcie.aml DROP_ASL="Kailua/APIC.aml" EXTRA_ASL="MCFG.aml APIC.aml" bash refs/build_acpi.sh Mu-pcie-its > /root/var2.log 2>&1
echo VARIANTS_DONE >> /root/var2.log
