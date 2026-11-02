import json,uuid,shutil
w=r"<RM9_WORKDIR>\winboot"
g=json.load(open(w+r"\bcd_vhd_guids.json",encoding="ascii-ignore" if False else "utf-8-sig"))
d=open(w+r"\BCD_raw","rb").read()
real={
 'disk':bytes.fromhex('c838aa6f3c29daceeb93e8c192caa430'),
 'esp': bytes.fromhex('40f96ec640d1f94ea072fa576fdf8584'),
 'win': bytes.fromhex('5bcc0cbe064bae4b833a1691f848d758'),
}
print({k:str(uuid.UUID(bytes_le=v)) for k,v in real.items()})
for k in ('disk','esp','win'):
    old=uuid.UUID(g[k].strip('{}')).bytes_le
    n=d.count(old); print(k,g[k],'occurrences',n)
    assert n>0
    d=d.replace(old,real[k])
open(w+r"\BCD_patched","wb").write(d)
print('ok',len(d))
