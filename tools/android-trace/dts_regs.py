#!/usr/bin/env python3
"""rpmh regulator nodes: resource-name (cmd-db id) <-> regulator-name <-> voltage range / mode / always-on, filtered for the WLAN/PCIe rails."""
import re
import sys

p = "/root/Mu-Silicium/Resources/DTBs/nx769j.dts"
lines = open(p, encoding="utf-8", errors="replace").read().split("\n")
want = sys.argv[1:] or ["s1c", "s2c", "s3c", "s6c", "l3c", "l15b", "s4i", "ldoe3", "ldod3", "ldod1", "ldod2"]
res = []
for i, l in enumerate(lines):
    m = re.search(r'qcom,resource-name = "([^"]+)"', l)
    if not m:
        continue
    # enclosing regulator children: scan forward until the parent block ends
    depth = 0
    blk = []
    # find parent node start
    j = i
    while j > 0 and not lines[j].rstrip().endswith("{"):
        j -= 1
    k = j
    d = 0
    for k in range(j, min(len(lines), j + 400)):
        d += lines[k].count("{") - lines[k].count("}")
        blk.append(lines[k])
        if d == 0:
            break
    res.append((m.group(1), blk))
for name, blk in res:
    if not any(w.lower() == name.lower() or name.lower().endswith(w.lower()) for w in want):
        continue
    print("=== resource %s" % name)
    for x in blk:
        if re.search(r"regulator-name|regulator-min-microvolt|regulator-max-microvolt|regulator-always-on|regulator-boot-on|qcom,init-voltage|qcom,init-mode|regulator-allowed-modes|qcom,resource-name|qcom,regulator-type|compatible|qcom,send-defaults|qcom,supported-modes|qcom,mode-threshold|qcom,drms-mode-max-microamp", x):
            print("   ", x.strip()[:150])
print("total regulator resources in DTS:", len(res))
print("all resource names:", " ".join(sorted(n for n, _ in res)))
