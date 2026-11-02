#!/usr/bin/env python3
"""Print the last N events of an .evtx (time, provider, id, short data).  evtx_tail.py file.evtx [N] [level<=]"""
import re
import sys
from Evtx.Evtx import Evtx

path = sys.argv[1]
n = int(sys.argv[2]) if len(sys.argv) > 2 else 60
rows = []
with Evtx(path) as log:
    for rec in log.records():
        x = rec.xml()
        t = re.search(r'SystemTime="([^"]+)"', x)
        pr = re.search(r'Provider Name="([^"]+)"', x)
        ei = re.search(r'<EventID[^>]*>(\d+)<', x)
        lv = re.search(r'<Level>(\d+)<', x)
        data = " ".join(re.findall(r'<Data[^>]*>([^<]*)<', x))[:170]
        rows.append((t.group(1) if t else "", pr.group(1) if pr else "", ei.group(1) if ei else "", lv.group(1) if lv else "", data))
for r in rows[-n:]:
    print(" | ".join(r))
