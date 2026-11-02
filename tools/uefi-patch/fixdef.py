p='<RM9_WORKDIR>/refs/MuChain.c'
s=open(p,encoding='utf-8',newline='').read()
proto_end=s.index('UINT32 HandleOff)\n{', s.index('STATIC VOID PmicDbgCall (UINT64 Base'))+len('UINT32 HandleOff)')
body_start=proto_end
body_end=s.index('\n}\n', body_start)+3
body=s[body_start:body_end]          # '\n{ ... \n}\n'
s=s[:body_start]+';\n'+s[body_end:]
# now replace the old definition
k=s.index('\nPmicDbgCall (UINT64 Base')
k2=s.index('UINT32 HandleOff)', k)+len('UINT32 HandleOff)')
e=s.index('\n}\n', k2)+3
s=s[:k2]+body+s[e:]
open(p,'w',encoding='utf-8',newline='').write(s)
print('ok')
