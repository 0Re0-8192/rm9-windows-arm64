#!/usr/bin/env python3
import re
p = "/root/Mu-Silicium/Resources/DTBs/nx769j.dts"
lines = open(p, encoding="utf-8", errors="replace").read().split("\n")


def node(i, maxn=120):
    depth = 0
    out = []
    for j in range(i, min(len(lines), i + 3000)):
        l = lines[j]
        d0 = depth
        depth += l.count("{") - l.count("}")
        if d0 <= 1:
            out.append(l.rstrip())
        if depth == 0:
            break
    return out[:maxn]


for i, l in enumerate(lines):
    if re.search(r"rsc@[0-9a-f]+ \{", l):
        print("######", l.strip(), "line", i + 1)
        for x in node(i):
            print(x[:230])
        print()
