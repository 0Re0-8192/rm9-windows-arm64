import struct,glob
for f in sorted(glob.glob(r"<RM9_WORKDIR>\dumps_new\cur\gpt_lun*.bin")):
    d=open(f,'rb').read(); n=len(d)//4096
    print(f.split('\\')[-1], n,'sectors; protective MBR sig', d[440:444].hex(), 'part0', d[446:462].hex())
    for i in range(n):
        if d[i*4096:i*4096+8]==b'EFI PART':
            h=d[i*4096:i*4096+92]; my,alt=struct.unpack_from('<QQ',h,24); print('   hdr at sector',i,'my',my,'alt',alt,'entLBA',struct.unpack_from('<Q',h,72)[0])
