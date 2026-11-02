#!/usr/bin/env python3
"""Emit a C array from the PCIe0 'qcom,phy-sequence' property (offset, value, delay_us triples) of the NX769J DTS (raw numbers)."""
import re
import sys

txt = open("/root/pcie0_node.txt", encoding="utf-8").read()
m = re.search(r"qcom,phy-sequence = <([^>]*)>", txt, re.S)
vals = [int(x, 16) for x in m.group(1).split()]
assert len(vals) % 3 == 0, len(vals)
rows = [vals[i:i + 3] for i in range(0, len(vals), 3)]
print("// %d entries (offset, value, delay_us) from DT qcom,phy-sequence of pcie@1c00000 (PHY base 0x1c06000)" % len(rows), file=sys.stderr)
out = ["STATIC CONST UINT16 mPciePhySeq[][3] = {"]
line = "  "
for r in rows:
    item = "{ 0x%X, 0x%X, %d }, " % tuple(r)
    if len(line) + len(item) > 110:
        out.append(line.rstrip())
        line = "  "
    line += item
out.append(line.rstrip())
out.append("};")
print("\n".join(out))
# interesting facts
delays = sorted(set(r[2] for r in rows))
print("// distinct delays:", delays, file=sys.stderr)
print("// first 6:", rows[:6], " last 6:", rows[-6:], file=sys.stderr)
