p = '<RM9_WORKDIR>/drv/rm9io/rm9io.c'
s = open(p, encoding='utf-8', newline='').read()
crlf = '\r\n' in s
s = s.replace('\r\n', '\n')

old = '#define SE4_PHYS 0xA90000ULL\n'
assert old in s
s = s.replace(old, old + '#define IOCTL_RM9_EDGES      CTL_CODE(RM9_DEVICE_TYPE, 0x805, METHOD_BUFFERED, FILE_ANY_ACCESS)\n', 1)

old = '} RM9_TOUCH_OUT;'
assert old in s
s = s.replace(old, old + '''
// IOCTL_RM9_EDGES: poll bit 0 of the 32-bit register at Phys as fast as possible for Ms milliseconds, count edges and record the time (us) of the first rising edges
typedef struct { UINT64 Phys; UINT32 Ms; UINT32 Mask; } RM9_EDGES_IN;
typedef struct { UINT32 Rising, Falling, Samples, ElapsedUs, HighSamples, Pad[3]; UINT32 Ts[32]; } RM9_EDGES_OUT;
''', 1)

a = 'static NTSTATUS Rm9Complete'
assert a in s
code = '''static NTSTATUS EdgeScan(RM9_EDGES_IN *In, RM9_EDGES_OUT *Out)
{
    PHYSICAL_ADDRESS Pa;
    PVOID Va;
    LARGE_INTEGER Freq, T0, T;
    ULONG Prev, Cur, Mask = In->Mask ? In->Mask : 1;
    ULONGLONG Lim;
    NTSTATUS St = STATUS_SUCCESS;

    RtlZeroMemory(Out, sizeof(*Out));
    if ((In->Phys & 3) || In->Ms == 0 || In->Ms > 2000) {
        return STATUS_INVALID_PARAMETER;
    }
    Pa.QuadPart = (LONGLONG)In->Phys;
    Va = MmMapIoSpaceEx(Pa, 4, PAGE_READWRITE | PAGE_NOCACHE);
    if (Va == NULL) {
        return STATUS_INSUFFICIENT_RESOURCES;
    }
    KeQueryPerformanceCounter(&Freq);
    T0 = KeQueryPerformanceCounter(&Freq);
    Lim = (ULONGLONG)Freq.QuadPart * In->Ms / 1000;
    __try {
        Prev = READ_REGISTER_ULONG((PULONG)Va) & Mask;
        for (;;) {
            Cur = READ_REGISTER_ULONG((PULONG)Va) & Mask;
            T = KeQueryPerformanceCounter(NULL);
            Out->Samples++;
            if (Cur) {
                Out->HighSamples++;
            }
            if (Cur != Prev) {
                if (Cur) {
                    if (Out->Rising < 32) {
                        Out->Ts[Out->Rising] = (UINT32)(((ULONGLONG)(T.QuadPart - T0.QuadPart) * 1000000ULL) / (ULONGLONG)Freq.QuadPart);
                    }
                    Out->Rising++;
                } else {
                    Out->Falling++;
                }
                Prev = Cur;
            }
            if ((ULONGLONG)(T.QuadPart - T0.QuadPart) >= Lim) {
                break;
            }
        }
        Out->ElapsedUs = (UINT32)(((ULONGLONG)(T.QuadPart - T0.QuadPart) * 1000000ULL) / (ULONGLONG)Freq.QuadPart);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        St = GetExceptionCode();
    }
    MmUnmapIoSpace(Va, 4);
    return St;
}

'''
s = s.replace(a, code + a, 1)

old = '    if (Code == IOCTL_RM9_TOUCH_START) {\n'
assert old in s
s = s.replace(old, '''    if (Code == IOCTL_RM9_EDGES) {
        if (InLen < sizeof(RM9_EDGES_IN) || OutLen < sizeof(RM9_EDGES_OUT)) {
            St = STATUS_BUFFER_TOO_SMALL;
        } else {
            RM9_EDGES_IN In = *(RM9_EDGES_IN *)Buf;
            St = EdgeScan(&In, (RM9_EDGES_OUT *)Buf);
            if (NT_SUCCESS(St)) {
                Info = sizeof(RM9_EDGES_OUT);
            }
        }
    }
''' + old.replace('    if (', '    else if (', 1), 1)
if crlf:
    s = s.replace('\n', '\r\n')
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
