#!/usr/bin/env python3
"""Print the properties (not sub-nodes) of the cnss/pcie nodes that matter for Wi-Fi bring-up, and resolve phandles to node names where possible."""
import re

p = "/root/Mu-Silicium/Resources/DTBs/nx769j.dts"
lines = open(p, encoding="utf-8", errors="replace").read().split("\n")

# phandle -> (node name, line index)
ph = {}
stack = []
for i, l in enumerate(lines):
    s = l.strip()
    if s.endswith("{"):
        stack.append(s[:-1].strip())
    elif s.startswith("};"):
        if stack:
            stack.pop()
    m = re.match(r"phandle = <(0x[0-9a-f]+)>;", s)
    if m and stack:
        ph[m.group(1)] = stack[-1]


def node_props(start, maxlines=400):
    depth = 0
    out = []
    for j in range(start, min(len(lines), start + maxlines)):
        l = lines[j]
        d_before = depth
        depth += l.count("{") - l.count("}")
        if d_before == 1 or (d_before == 0 and "{" in l):
            out.append(l.rstrip())
        if depth == 0:
            break
    return out


def show(pattern, title):
    for i, l in enumerate(lines):
        if re.search(pattern, l) and l.strip().endswith("{"):
            print("\n######", title, "(line %d)" % (i + 1))
            for x in node_props(i):
                x2 = re.sub(r"<([0-9a-fx ]+)>", lambda m: "<" + " ".join(ph.get(t, t) if t.startswith("0x") and t in ph else t for t in m.group(1).split()) + ">", x)
                print(x2[:260])
            return


show(r"qcom,cnss-kiwi@b0000000 \{", "cnss-kiwi")
show(r"qcom,pcie@1c08000 \{", "pcie1 (0x1c08000)")
show(r"qcom,pcie@1c00000 \{", "pcie0 (0x1c00000)")
