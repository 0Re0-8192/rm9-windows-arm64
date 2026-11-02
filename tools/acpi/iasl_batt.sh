#!/bin/bash
cd <RM9_WORKDIR>/refs/acpi/nx769j
iasl -tc -f DSDT_batt.dsl 2>&1 | tail -25
ls -la DSDT_batt.aml 2>&1 | awk '{print $5,$9}'
