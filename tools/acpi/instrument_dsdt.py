#!/usr/bin/env python3
"""Instrument a decompiled DSDT.dsl so every _STA/_CRS/_DSM/_LPI/_PS0/_PS3/_INI/_OSC/_DEP/_PSC evaluation
is logged into reserved memory (end of the Mu RAM console, 0xD7FF0000), readable afterwards through
the Sahara RAMCON dump.  Also adds \\_SB._INI.

  instrument_dsdt.py in.dsl out.dsl map.txt

Layout at 0xD7FF0000 (all u32):
  0x000          total event count
  0x004..0x083   ring of the last 32 events:  ((Timer() << 8) | event_id) & 0xFFFFFFFF
  0x084..0x103   per-event-id counters C[0..31]   (event ids are < 32)
MuChain keeps its own markers at 0xD7FF0400 and above.
"""
import re
import sys

BASE = 0xD7FF0000
METHODS = r"(_STA|_CRS|_DSM|_LPI|_PS0|_PS3|_INI|_OSC|_DEP|_PSC)"

lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
out = []
mapping = []
dev_stack = []        # [(device name, brace depth at its opening)]
depth = 0
event = 2
pending_dev = None
inject_next = None    # (event, method, path)

for ln in lines:
    s = ln.strip()
    out.append(ln)
    if inject_next and s == "{":
        ev, meth, path = inject_next
        out.append("                DBGL (0x%02X)  // trace %s %s" % (ev, meth, path))
        inject_next = None
    m = re.match(r"Device \((\w+)\)", s)
    if m:
        pending_dev = m.group(1)
    mm = re.match(r"Method \(%s\b" % METHODS, s)
    if mm:
        path = "/".join(n for n, _ in dev_stack) or "_SB"
        inject_next = (event, mm.group(1), path)
        mapping.append((event, mm.group(1), path))
        event += 1
    if s == "{" and pending_dev:
        dev_stack.append((pending_dev, depth))
        pending_dev = None
    depth += ln.count("{") - ln.count("}")
    while dev_stack and depth <= dev_stack[-1][1]:
        dev_stack.pop()

assert event < 32, "too many events for the 32-entry counter table"
text = "\n".join(out)

fields = ",\n".join("            L%02d,   32" % k for k in range(32))
cfields = ",\n".join("            C%02d,   32" % k for k in range(32))
ifs = "\n".join("            If (Local1 == 0x%02X) { L%02d = Local2 }" % (k, k) for k in range(32))
cifs = "\n".join("            If (Local3 == 0x%02X) { C%02d = C%02d + 1 }" % (k, k, k) for k in range(32))
region = """        OperationRegion (DBG0, SystemMemory, 0x%08X, 0x200)
        Field (DBG0, DWordAcc, NoLock, Preserve)
        {
            CNT0,   32,
%s,
%s
        }

        Method (DBGL, 1, NotSerialized)
        {
            Local0 = CNT0
            CNT0 = Local0 + 1
            Local1 = Local0 & 0x1F
            Local2 = (Timer << 8) | (Arg0 & 0xFF)
%s
            Local3 = Arg0 & 0x1F
%s
        }

        Method (_INI, 0, NotSerialized)  // _INI: Initialize
        {
            DBGL (0x01)
        }

""" % (BASE, fields, cfields, ifs, cifs)

marker = "    Scope (_SB)\n    {\n"
assert marker in text, "Scope (_SB) not found"
text = text.replace(marker, marker + region, 1)
open(sys.argv[2], "w", encoding="utf-8").write(text)
with open(sys.argv[3], "w", encoding="utf-8") as f:
    f.write("0x01\t_INI\t_SB\n")
    for ev, meth, path in mapping:
        f.write("0x%02X\t%s\t%s\n" % (ev, meth, path))
print("instrumented %d methods" % len(mapping))
