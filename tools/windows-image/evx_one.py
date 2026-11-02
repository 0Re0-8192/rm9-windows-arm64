import re, sys, html
import Evtx.Evtx as e
f, ts0 = sys.argv[1], sys.argv[2]
with e.Evtx(f) as log:
    for r in log.records():
        x = r.xml()
        if ts0 in x:
            print(html.unescape(re.sub(r'<[^>]+>', ' ', x))[:2500])
