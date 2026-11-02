import struct,sys
d=open(sys.argv[1],'rb').read()
print(len(d))
# Sahara memory debug table: 64-byte entries (save_pref u64, base u64, len u64, desc 20 bytes, filename 20 bytes)
for off in range(0,len(d)-64+1,64):
    e=d[off:off+64]
    sp,base,ln=struct.unpack_from('<QQQ',e,0)
    desc=e[24:44].split(b'\0')[0].decode('latin1'); fn=e[44:64].split(b'\0')[0].decode('latin1')
    if ln: print('%2d base=0x%010x len=0x%09x (%7.1f MB) %-20s %s'%(off//64,base,ln,ln/1048576,desc,fn))
