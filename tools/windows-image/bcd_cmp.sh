#!/bin/bash
cd <RM9_WORKDIR>
/root/.venv/bin/python3 refs/bcd_dump.py winboot/BCD.after17_20 > /tmp/bcd_orig.txt 2>&1
/root/.venv/bin/python3 refs/bcd_dump.py backups/esp_after3231/BCD > /tmp/bcd_mod.txt 2>&1
wc -l /tmp/bcd_orig.txt /tmp/bcd_mod.txt
diff /tmp/bcd_orig.txt /tmp/bcd_mod.txt | head -30
echo ---- orig summary
grep -E "OBJECT|^   (12000004|12000002|22000002|23000003|25000004|26000020|250000e0|16000010|1600007b)" /tmp/bcd_orig.txt | head -40
