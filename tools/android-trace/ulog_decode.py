import re,struct,sys
t=open(sys.argv[1],encoding='utf-8',errors='replace').read().splitlines()
sec=None;out={}
for l in t:
    m=re.search(r'CDBG (ulog[\w\-]*): captured',l)
    if m: sec=m.group(1); out.setdefault(sec,{}); continue
    if re.search(r'CDBG (?!ulog)',l): sec=None
    m=re.search(r'\brx ([0-9A-F]{4,6}): ((?:[0-9A-F]{8} ?){8})',l)
    if m and sec:
        off=int(m.group(1),16)
        for i,w in enumerate(m.group(2).split()):
            out[sec][off+4*i]=int(w,16)
for s,d in out.items():
    ks=sorted(d)
    b=b''.join(struct.pack('<I',d[k]) for k in ks)
    txt=''.join(chr(c) if 32<=c<127 or c==10 else '.' for c in b)
    print('==',s,len(b)); print(txt)
