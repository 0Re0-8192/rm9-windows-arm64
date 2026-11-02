import struct,sys
d=open("/root/SYSTEM.device","rb").read(512)
sig=d[:4]; s1,s2=struct.unpack_from("<II",d,4); major,minor=struct.unpack_from("<II",d,0x14); flags=struct.unpack_from("<I",d,0x90)[0] if len(d)>0x94 else None
print("sig",sig,"seq1",s1,"seq2",s2,"clean" if s1==s2 else "DIRTY (needs LOG replay)","ver %d.%d"%(major,minor))
