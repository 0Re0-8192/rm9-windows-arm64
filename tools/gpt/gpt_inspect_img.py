import struct,sys,zlib
f=open('/root/qemu/disk2_pe.img','rb'); T=61521920; S=4096
def hdr(lba):
    f.seek(lba*S); h=f.read(S)
    if h[:8]!=b'EFI PART': return None
    my,alt,fu,lu=struct.unpack_from('<QQQQ',h,24); el,n,sz=struct.unpack_from('<QII',h,72)
    crc=struct.unpack_from('<I',h,16)[0]
    hh=bytearray(h[:92]); hh[16:20]=b'\0\0\0\0'
    return dict(my=my,alt=alt,first=fu,last=lu,entLBA=el,n=n,sz=sz,crc=crc,crc_ok=(zlib.crc32(bytes(hh))&0xffffffff)==crc)
print('primary',hdr(1)); print('backup ',hdr(T-1))
def ents(lba,n=128,sz=128):
    f.seek(lba*S); d=f.read(n*sz); return d,zlib.crc32(d)&0xffffffff
for lba in (2,5,T-33,T-32,T-4,T-1):
    d,c=ents(lba); print('entries@',lba,'nonzero' if any(d) else 'ZERO',hex(c))
