p = '<RM9_WORKDIR>/drv/rm9io/rm9io.c'
s = open(p, encoding='utf-8', newline='').read()
crlf = '\r\n' in s
s = s.replace('\r\n', '\n')
touch = open('<RM9_WORKDIR>/drv/rm9io/touch_part.c', encoding='utf-8').read()

old = '#define IOCTL_RM9_WRITE CTL_CODE(RM9_DEVICE_TYPE, 0x801, METHOD_BUFFERED, FILE_ANY_ACCESS)\n'
assert old in s
s = s.replace(old, old + '''// Touch (Goodix BRL-D on GENI SE4 SPI).  MuChain (TOUCH.TXT, Windows boot) powers the panel IC, sets pins/clocks, maps SMMU stream 0xA3 and initialises SE4; this driver runs the SPI DMA transfers.
#define IOCTL_RM9_TOUCH_START CTL_CODE(RM9_DEVICE_TYPE, 0x802, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_RM9_TOUCH_GET   CTL_CODE(RM9_DEVICE_TYPE, 0x803, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_RM9_TOUCH_STOP  CTL_CODE(RM9_DEVICE_TYPE, 0x804, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define SE4_PHYS 0xA90000ULL
''', 1)

old = '#pragma pack(pop)\n'
assert old in s
s = s.replace(old, '''typedef struct {
    UINT32 Seq;          // frames with status != 0 so far
    UINT32 Polls;        // transfers attempted
    UINT32 Errors;       // failed transfers
    UINT32 Running;
    UINT32 LastTd, LastRd, LastM;   // DMA tx/rx/main IRQ status of the last failed transfer
    UINT32 Confirm;      // first poll: register 0x2000 as a LE word, 0xFFFFFFFF if the read failed
    UINT8  Frame[26];    // last frame with status != 0 (read from 0x10308)
    UINT8  Pad[2];
} RM9_TOUCH_OUT;
#pragma pack(pop)
''', 1)

old = 'static NTSTATUS Rm9Complete'
assert old in s
s = s.replace(old, touch + old, 1)

old = '    return Rm9Complete(Irp, St, Info);\n}\n\nVOID Rm9Unload'
assert old in s
s = s.replace(old, '''    if (Code == IOCTL_RM9_TOUCH_START) {
        St = TouchStart();
    } else if (Code == IOCTL_RM9_TOUCH_GET) {
        if (OutLen < sizeof(RM9_TOUCH_OUT)) {
            St = STATUS_BUFFER_TOO_SMALL;
        } else {
            RtlCopyMemory(Buf, (PVOID)&g_Touch, sizeof(RM9_TOUCH_OUT));
            Info = sizeof(RM9_TOUCH_OUT);
            St = STATUS_SUCCESS;
        }
    } else if (Code == IOCTL_RM9_TOUCH_STOP) {
        TouchStopAndWait();
        St = STATUS_SUCCESS;
    }
''' + old, 1)

old = '    IoDeleteSymbolicLink(&Link);\n    if (Drv->DeviceObject)'
assert old in s
s = s.replace(old, '    TouchStopAndWait();\n' + old, 1)
if crlf:
    s = s.replace('\n', '\r\n')
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
