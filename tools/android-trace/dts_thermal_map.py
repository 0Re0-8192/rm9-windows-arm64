#!/usr/bin/env python3
"""zone name -> (tsens controller, sensor index) from the NX769J device tree (thermal-zones { <name> { thermal-sensors = <&tsensN idx>; }}).
Phandles are resolved through the 'phandle' of the tsens nodes."""
import re
import sys

p = "/root/Mu-Silicium/Resources/DTBs/nx769j.dts"
txt = open(p, encoding="utf-8", errors="replace").read()
# phandle -> tsens node name
ph = {}
for m in re.finditer(r"(tsens\d)@[0-9a-f]+\s*\{(.*?)\n\t\t\};", txt, re.S):
    mm = re.search(r"phandle\s*=\s*<(0x[0-9a-f]+)>", m.group(2))
    if mm:
        ph[mm.group(1)] = m.group(1)
print("tsens phandles:", ph, file=sys.stderr)
i = txt.index("thermal-zones {")
depth = 0
j = i
while True:
    c = txt[j]
    if c == "{":
        depth += 1
    elif c == "}":
        depth -= 1
        if depth == 0:
            break
    j += 1
blk = txt[i:j + 1]
rows = []
for m in re.finditer(r"\n\t\t\t([\w\-]+) \{(.*?)\n\t\t\t\};", blk, re.S):
    name, body = m.group(1), m.group(2)
    ts = re.search(r"thermal-sensors\s*=\s*<(0x[0-9a-f]+)\s+(0x[0-9a-f]+|\d+)>", body)
    if ts:
        if ts.group(1) in ph: rows.append((name, ph[ts.group(1)], int(ts.group(2), 0)))
for name, t, idx in sorted(rows, key=lambda r: (r[1], r[2])):
    print("%-10s %2d  %s" % (t, idx, name))
