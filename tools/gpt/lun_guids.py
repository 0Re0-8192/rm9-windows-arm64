import struct,glob,uuid
for f in sorted(glob.glob(r"<RM9_WORKDIR>\dumps_new\cur\gpt_lun*.bin")):
    d=open(f,'rb').read()
    # find header: LBA1 at 512 or 4096
    for ss in (4096,512):
        if d[ss:ss+8]==b'EFI PART':
            h=d[ss:ss+92]
            my,alt,fu,lu=struct.unpack_from('<QQQQ',h,24)
            print(f.split('\\')[-1],'sector',ss,'diskGUID',uuid.UUID(bytes_le=h[56:72]),'my',my,'alt',alt,'first',fu,'last',lu,'entLBA',struct.unpack_from('<Q',h,72)[0],'n',struct.unpack_from('<I',h,80)[0])
            break
    else: print(f,'no hdr',len(d))
