p='<RM9_WORKDIR>/refs/MuChain.c'
s=open(p,encoding='utf-8',newline='').read()
BS=chr(92)
a='    mDbgOwner = 0x800A;\n    PmicDbgCall (Base, "ulog-set"'
assert a in s
dump='''    {
      UINT32  Hi, Hj;
      for (Hi = 0; Hi < 0x110; Hi += 8) {
        UINT64  V = *(UINT64 *)(UINTN)(Base + 0xA370 + Hi);
        PL ("PGDATA +%x = %lx", 0xA370 + Hi, V);
        if (V > 0x80000000ULL && V < 0x1000000000ULL && (V & 7) == 0 && Hi != 0) {
          PL (" ->");
          for (Hj = 0; Hj < 12; Hj++) {
            PL (" %lx", *(UINT64 *)(UINTN)(V + Hj * 8));
          }
        }
        PL ("''' + BS + '''n");
      }
    }
'''
s=s.replace(a,dump+a,1)
open(p,'w',encoding='utf-8',newline='').write(s)
