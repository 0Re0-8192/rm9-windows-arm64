#!/usr/bin/env python3
"""Pull the SPMI arbiter node(s) and the RTC's parent (PMIC sid) out of the NX769J DTS."""
import re

p = "/root/Mu-Silicium/Resources/DTBs/nx769j.dts"
txt = open(p, encoding="utf-8", errors="replace").read()
lines = txt.split("\n")


def block_at(idx):
    """return the lines of the node whose opening line is lines[idx]"""
    depth = 0
    out = []
    for j in range(idx, len(lines)):
        l = lines[j]
        out.append(l)
        depth += l.count("{") - l.count("}")
        if depth == 0:
            break
    return out


for i, l in enumerate(lines):
    if re.search(r"spmi@[0-9a-f]+ \{", l) and "pmic-arb" in "\n".join(block_at(i)[:40]):
        b = block_at(i)
        print("=== arbiter node:", l.strip())
        for x in b[:45]:
            if re.search(r"compatible|reg|ee|channel|bus|interrupt", x):
                print(x)
        break

# find rtc node and walk back to its enclosing pmic@N
for i, l in enumerate(lines):
    if re.search(r"rtc@6100 \{", l):
        print("=== rtc node line", i + 1)
        for x in block_at(i)[:12]:
            print(x)
        # enclosing parents: scan backward by indentation
        ind = len(l) - len(l.lstrip("\t"))
        for j in range(i - 1, 0, -1):
            lj = lines[j]
            if lj.strip().endswith("{") and (len(lj) - len(lj.lstrip("\t"))) < ind:
                print("parent:", lj.strip(), "(line %d)" % (j + 1))
                ind = len(lj) - len(lj.lstrip("\t"))
                if "pmic@" in lj or "spmi" in lj:
                    for x in block_at(j)[:14]:
                        if re.search(r"reg|compatible|#", x):
                            print("   ", x)
                    break
        break
