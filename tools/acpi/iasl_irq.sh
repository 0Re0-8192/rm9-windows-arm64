#!/bin/bash
cd <RM9_WORKDIR>/refs/acpi/nx769j
iasl -tc -f DSDT_pcie5.dsl 2>&1 | tail -25
ls -la DSDT_pcie5.aml 2>&1 | awk '{print $5,$9}'
