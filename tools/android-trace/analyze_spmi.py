# -*- coding: utf-8 -*-
from pathlib import Path
import re

dts = Path(r'C:\Users\<user>\.local\share\opencode\tool-output\tool_12f1e7a3f001bn316lXxdAgMpF').read_text(encoding='utf-8', errors='replace')
drv = Path(r'C:\Users\<user>\.local\share\opencode\tool-output\tool_12f1e7a420014ueDA86uJyYaEb').read_text(encoding='utf-8', errors='replace')

print('=== DTS: whole spmi node ===')
m = re.search(r'spmi_bus: spmi@c400000 \{.*?\n\t\t\};', dts, re.S)
print(m.group(0)[:1600] if m else 'not found')
print()

print('=== driver: v7/v8 entries of the of_device_id match table ===')
lines = drv.splitlines()
in_table = False
for i, ln in enumerate(lines):
    if 'of_device_id' in ln or 'qcom,spmi-pmic-arb' in ln:
        for j in range(i, min(len(lines), i + 40)):
            t = lines[j]
            if 'sm8650' in t or 'pmic_arb_v' in t or 'compatible' in t:
                print('%5d %s' % (j, t.strip()[:160]))
print()
print('=== driver: clocks / power / hw init in probe ===')
for i, ln in enumerate(lines):
    if re.search(r'devm_clk|clk_get|pm_runtime|power_domain|hw_init|reset_control|qcom,ee|"ee"|of_property_read_u8', ln):
        print('%5d %s' % (i, ln.strip()[:160]))
