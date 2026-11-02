import struct,sys
d=open('<RM9_WORKDIR>/winboot/slota/sde_head3.bin','rb').read()
ss=4096
hdr=d[ss:ss+92]
sig=hdr[:8]; nent=struct.unpack('<I',hdr[80:84])[0]; esz=struct.unpack('<I',hdr[84:88])[0]; lba=struct.unpack('<Q',hdr[72:80])[0]
print(sig,nent,esz,lba)
ents=d[lba*ss:lba*ss+nent*esz]
for i in range(nent):
    e=ents[i*esz:(i+1)*esz]
    if e[:16]==b'\0'*16: continue
    name=e[56:128].decode('utf-16-le','ignore').split('\0')[0]
    if name in ('boot_a','boot_b','vendor_boot_a','vendor_boot_b','abl_a','abl_b','init_boot_a','init_boot_b','vbmeta_a','vbmeta_b'):
        attr=struct.unpack('<Q',e[48:56])[0]
        prio=(attr>>48)&3; active=(attr>>50)&1; retry=(attr>>51)&7; succ=(attr>>54)&1; unb=(attr>>55)&1
        print('%-14s idx=%2d attr=%016x prio=%d active=%d retry=%d successful=%d unbootable=%d'%(name,i+1,attr,prio,active,retry,succ,unb))
