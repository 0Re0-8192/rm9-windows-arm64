#!/bin/bash
cd <RM9_WORKDIR>/refs/acpi/nx769j
iasl -tc -f DSDT_pcie.dsl 2>&1 | tail -25
ls -la DSDT_pcie.aml 2>&1 | awk '{print $5,$9}'
