"""List recent application-crash style events from a copied Application.evtx.  usage: evx_crash.py <Application.evtx> [name-filter]"""
import re
import sys

import Evtx.Evtx as e

f = sys.argv[1]
flt = sys.argv[2] if len(sys.argv) > 2 else ''
out = []
with e.Evtx(f) as log:
    for r in log.records():
        x = r.xml()
        m = re.search(r'<EventID[^>]*>(\d+)<', x)
        eid = m.group(1) if m else '?'
        if eid in ('1000', '1001', '1002', '1026') or (flt and flt in x):
            t = re.search(r'SystemTime="([^"]+)"', x)
            d = re.findall(r'<Data[^>]*>([^<]*)<', x)
            out.append((t.group(1) if t else '', eid, ' | '.join(d)[:260]))
for o in out[-30:]:
    print(*o)
print('total', len(out))
