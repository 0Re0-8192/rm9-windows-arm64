"""events since a timestamp prefix from Application.evtx. usage: evx_since.py <evtx> <YYYY-MM-DD HH>"""
import re, sys
import Evtx.Evtx as e
f, since = sys.argv[1], sys.argv[2]
rows = []
with e.Evtx(f) as log:
    for r in log.records():
        x = r.xml()
        t = re.search(r'SystemTime="([^"]+)"', x)
        ts = t.group(1) if t else ''
        if ts >= since.replace(' ', 'T') or ts[:13].replace('T', ' ') >= since:
            m = re.search(r'<EventID[^>]*>(\d+)<', x)
            d = re.findall(r'<Data[^>]*>([^<]*)<', x)
            rows.append((ts, m.group(1) if m else '?', ' | '.join(d)[:240]))
rows.sort()
for o in rows[:60]: print(*o)
print('total', len(rows))
