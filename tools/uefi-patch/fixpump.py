p='<RM9_WORKDIR>/refs/MuChain.c'
s=open(p,encoding='utf-8',newline='').read()
BS=chr(92)
i=s.index('    UINT32  Pi, C0 = mIpccPollCalls;')
j=s.index('\n',i)
line=s[i:j]
fixed=line.replace(BS+'n    ','\n    ').replace(BS+'n  }','\n  }')
# restore the one real '\n' inside the PL format string (after 'head %x')
fixed=fixed.replace('head %x\n", Tag','head %x'+BS+'n", Tag')
s=s[:i]+fixed+s[j:]
open(p,'w',encoding='utf-8',newline='').write(s)
