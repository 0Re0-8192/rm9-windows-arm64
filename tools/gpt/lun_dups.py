import struct,uuid,collections,zlib
R=r"<RM9_WORKDIR>\dumps_new\cur\gpt_lun%d.bin"
seen=collections.defaultdict(list); hdrs={}
for n in range(6):
    d=open(R%n,'rb').read(); h=d[4096:4096+92]
    hdrs[n]=h
    nent=struct.unpack_from('<I',h,80)[0]
    for i in range(nent):
        e=d[8192+i*128:8192+(i+1)*128]
        if e[:16]==b'\0'*16: continue
        seen[uuid.UUID(bytes_le=e[16:32])].append((n,i,e[56:128].decode('utf-16le').rstrip('\0')))
dups={g:v for g,v in seen.items() if len(v)>1}
print("partitions:",sum(len(v) for v in seen.values()),"duplicate unique-partition GUIDs:",len(dups))
for g,v in list(dups.items())[:10]: print(g,v)
print("header CRCs / entries-crc per LUN:")
for n,h in hdrs.items(): print(n,'hdrcrc',hex(struct.unpack_from('<I',h,16)[0]),'entcrc',hex(struct.unpack_from('<I',h,88)[0]))
