// dbgcap.sys - captures every DbgPrint/DbgPrintEx line of the running kernel (what DebugView's "Capture Kernel" does) into a ring buffer;
// user mode reads it with IOCTL 0x8F002800 on \.\dbgcap.  Used to see the qcwlan (WCN7850) driver's own MHI/boot log messages.
#include <ntddk.h>
#include <wdmsec.h>
#include <arm64intr.h>
#include <intrin.h>
#include <string.h>

#define DEV_TYPE 0x8F00
#define IOCTL_DBGCAP_READ CTL_CODE(DEV_TYPE, 0xA00, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_DBGCAP_READVA CTL_CODE(DEV_TYPE, 0xA01, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_DBGCAP_LPITEST CTL_CODE(DEV_TYPE, 0xA02, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define ICC_IAR1 ARM64_SYSREG(3, 0, 12, 12, 0)
#define ICC_EOIR1 ARM64_SYSREG(3, 0, 12, 12, 1)
#define ICC_PMR ARM64_SYSREG(3, 0, 4, 6, 0)
#define ICC_RPR ARM64_SYSREG(3, 0, 12, 11, 3)
#define ICC_IGRPEN1 ARM64_SYSREG(3, 0, 12, 12, 7)
#define ICC_CTLR ARM64_SYSREG(3, 0, 12, 12, 4)
#define ICC_BPR1 ARM64_SYSREG(3, 0, 12, 12, 3)
#define IOCTL_DBGCAP_ITSSTORM CTL_CODE(DEV_TYPE, 0xA03, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_DBGCAP_HPPIR CTL_CODE(DEV_TYPE, 0xA04, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define ICC_HPPIR1 ARM64_SYSREG(3, 0, 12, 12, 2)
#define ICC_AP1R0 ARM64_SYSREG(3, 0, 12, 9, 0)
#define IOCTL_DBGCAP_TIMING CTL_CODE(DEV_TYPE, 0xA05, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_DBGCAP_POLL CTL_CODE(DEV_TYPE, 0xA06, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_DBGCAP_PREV CTL_CODE(DEV_TYPE, 0xA07, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_DBGCAP_WDTTEST CTL_CODE(DEV_TYPE, 0xA08, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_DBGCAP_GOV CTL_CODE(DEV_TYPE, 0xA0A, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define RING_SIZE (1u << 20)

typedef VOID (*PDEBUG_PRINT_CALLBACK_T)(PSTRING Output, ULONG ComponentId, ULONG Level);
typedef NTSTATUS (NTAPI *PFN_SET_CB)(PDEBUG_PRINT_CALLBACK_T, BOOLEAN);
typedef NTSTATUS (NTAPI *PFN_SET_FILTER)(ULONG, ULONG, BOOLEAN);

static PUCHAR g_Ring;
static KSPIN_LOCK g_Lock;
static volatile LONG g_Head;          // bytes ever reserved
static volatile LONG g_Tail;          // bytes already handed to the reader
static PFN_SET_CB g_SetCb;

DRIVER_INITIALIZE DriverEntry;
DRIVER_UNLOAD DcUnload;
_Dispatch_type_(IRP_MJ_CREATE) _Dispatch_type_(IRP_MJ_CLOSE) DRIVER_DISPATCH DcCreateClose;
_Dispatch_type_(IRP_MJ_DEVICE_CONTROL) DRIVER_DISPATCH DcIoctl;

static const char Hex[] = "0123456789ABCDEF";

static VOID PutBytes(const UCHAR *s, ULONG n)
{
    ULONG pos, i;
    KIRQL old = KeGetCurrentIrql();
    BOOLEAN raised = (old < DISPATCH_LEVEL);
    if (raised) KeAcquireSpinLock(&g_Lock, &old); else KeAcquireSpinLockAtDpcLevel(&g_Lock);
    pos = (ULONG)g_Head; g_Head = (LONG)(pos + n);
    if (raised) KeReleaseSpinLock(&g_Lock, old); else KeReleaseSpinLockFromDpcLevel(&g_Lock);
    for (i = 0; i < n; i++) g_Ring[(pos + i) & (RING_SIZE - 1)] = s[i];
}

static VOID DcCallback(PSTRING Output, ULONG Comp, ULONG Level)
{
    UCHAR pre[40];
    ULONG k = 0, i;
    ULONGLONG ms = KeQueryInterruptTime() / 10000;
    ULONG len;
    // "[mmmmmmmm cc ll] text"
    pre[k++] = '[';
    for (i = 0; i < 8; i++) pre[k++] = (UCHAR)Hex[(ms >> (28 - 4 * i)) & 15];
    pre[k++] = ' ';
    pre[k++] = (UCHAR)Hex[(Comp >> 4) & 15]; pre[k++] = (UCHAR)Hex[Comp & 15];
    pre[k++] = ' ';
    pre[k++] = (UCHAR)Hex[(Level >> 4) & 15]; pre[k++] = (UCHAR)Hex[Level & 15];
    pre[k++] = ']'; pre[k++] = ' ';
    PutBytes(pre, k);
    len = Output->Length;
    if (len > 1000) len = 1000;
    PutBytes((const UCHAR *)Output->Buffer, len);
    if (len == 0 || Output->Buffer[len - 1] != '\n') { UCHAR nl = '\n'; PutBytes(&nl, 1); }
}


// IOCTL_DBGCAP_LPITEST  in: { ULONG Cpu; ULONG DevId; ULONG EventId; ULONG Usec }   out: { ULONG RanOnCpu; ULONG Count; ULONG Ids[8]; ULONG Pre; }
// Pins the thread to Cpu, raises IRQL to HIGH_LEVEL (CPU interface interrupts masked), appends INT(DevId, EventId) + SYNC to the ITS command queue and then polls ICC_IAR1_EL1: the INTIDs that
// come back were acknowledged by hand (and are EOI'd), i.e. they really reached this CPU's interface.
static PUCHAR g_ItsRegs;
static PUCHAR g_ItsQueue;
static ULONGLONG g_ItsQueuePa;

static NTSTATUS LpiTest(PULONG in, PULONG out)
{
    ULONG cpu = in[0], dev = in[1], ev = in[2], usec = in[3], count = 0, i;
    BOOLEAN sgiMode;
    KAFFINITY prevAff;
    KIRQL oldIrql;
    LARGE_INTEGER freq, t0, t1;
    ULONG cw, cr;
    ULONGLONG qpa;
    PHYSICAL_ADDRESS pa;

    if (!g_ItsRegs) {
        pa.QuadPart = 0x17140000;
        g_ItsRegs = (PUCHAR)MmMapIoSpace(pa, 0x1000, MmNonCached);
        if (!g_ItsRegs) return STATUS_INSUFFICIENT_RESOURCES;
    }
    qpa = ((ULONGLONG)READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x84)) << 32 | READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x80))) & 0x000FFFFFFFFFF000ull;
    if (!g_ItsQueue || qpa != g_ItsQueuePa) {
        if (g_ItsQueue) MmUnmapIoSpace(g_ItsQueue, 0x1000);
        pa.QuadPart = (LONGLONG)qpa;
        g_ItsQueue = (PUCHAR)MmMapIoSpace(pa, 0x1000, MmNonCached);
        g_ItsQueuePa = qpa;
        if (!g_ItsQueue) return STATUS_INSUFFICIENT_RESOURCES;
    }
    RtlZeroMemory(out, 22 * sizeof(ULONG));
    prevAff = KeSetSystemAffinityThreadEx((KAFFINITY)1 << cpu);
    out[0] = KeGetCurrentProcessorNumberEx(NULL);
    KeQueryPerformanceCounter(&freq);
    KeRaiseIrql(HIGH_LEVEL, &oldIrql);
    out[14] = (ULONG)_ReadStatusReg(ICC_PMR); out[15] = (ULONG)_ReadStatusReg(ICC_RPR); out[16] = (ULONG)_ReadStatusReg(ICC_IGRPEN1);
    out[17] = (ULONG)_ReadStatusReg(ICC_CTLR); out[18] = (ULONG)_ReadStatusReg(ICC_BPR1);
    _disable();                                                            // mask IRQs at the PE (DAIF.I): Windows masks by priority only, so opening PMR would let its own handler take the interrupt first
    sgiMode = (usec & 0x40000000u) != 0;
    if (usec & 0x80000000u) { _WriteStatusReg(ICC_PMR, 0xFF); }
    usec &= 0x3FFFFFFFu;       // bit 31 of Usec = open the priority mask for the test
    out[19] = (ULONG)_ReadStatusReg(ICC_PMR);
    out[20] = (ULONG)_ReadStatusReg(ARM64_SYSREG(3, 0, 4, 2, 2));          // CurrentEL
    out[21] = (ULONG)_ReadStatusReg(ARM64_SYSREG(3, 0, 12, 12, 5));         // ICC_SRE_EL1
    {
        ULONGLONG a = (ULONGLONG)_ReadStatusReg(ICC_IAR1) & 0xFFFFFF;       // drain whatever is pending first
        out[10] = (ULONG)a;
        if (a != 1023 && a != 1022 && a != 1020 && a != 1021) _WriteStatusReg(ICC_EOIR1, (__int64)a);
    }
    cw = READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x88)); cr = READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x90));
    out[11] = cw; out[12] = cr;
    if (sgiMode) {
        // positive control: SGI 1 to ourselves (Aff1 = cpu, Aff0 target list bit 0), acknowledged by hand below
        _WriteStatusReg(ARM64_SYSREG(3, 0, 12, 11, 5), (__int64)((1ULL << 24) | ((ULONGLONG)cpu << 16) | 1ULL));
        __isb(_ARM64_BARRIER_SY);
    } else if (cw == cr) {
        PULONG c = (PULONG)(g_ItsQueue + (cw & 0xFE0));
        ULONG nxt = (cw + 0x20) & 0xFFF, nxt2;
        // INT dev, event
        for (i = 0; i < 8; i++) c[i] = 0;
        c[0] = 3; c[1] = dev; c[2] = ev;
        c = (PULONG)(g_ItsQueue + nxt);
        for (i = 0; i < 8; i++) c[i] = 0;
        c[0] = 5;                                                               // SYNC RDbase 0 (the collection's target is whatever was set up beforehand)
        c[4] = cpu << 16;
        nxt2 = (nxt + 0x20) & 0xFFF;
        KeMemoryBarrier();
        WRITE_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x88), nxt2);
    }
    t0 = KeQueryPerformanceCounter(NULL);
    do {
        ULONGLONG a = (ULONGLONG)_ReadStatusReg(ICC_IAR1) & 0xFFFFFF;
        if (a != 1023) {
            ULONG k, known = 0;                                   // DISTINCT: record each INTID once (a level timer PPI would otherwise fill the list)
            for (k = 0; k < count && k < 8; k++) if (out[2 + k] == (ULONG)a) known = 1;
            if (!known && count < 8) out[2 + count++] = (ULONG)a;
            out[1 + 0] = 0;
            if (a != 1022 && a != 1020 && a != 1021) _WriteStatusReg(ICC_EOIR1, (__int64)a);
        }
        t1 = KeQueryPerformanceCounter(NULL);
    } while ((ULONGLONG)(t1.QuadPart - t0.QuadPart) * 1000000ull / (ULONGLONG)freq.QuadPart < usec);
    if (in[3] & 0x80000000u) _WriteStatusReg(ICC_PMR, (__int64)out[14]);
    _enable();
    KeLowerIrql(oldIrql);
    KeRevertToUserAffinityThreadEx(prevAff);
    out[13] = READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x90));
    out[1] = count;
    return STATUS_SUCCESS;
}

// IOCTL_DBGCAP_ITSSTORM  in: { ULONG DevId; ULONG EventId; ULONG Count }   out: { ULONG Sent; ULONG Cw; ULONG Cr; ULONG Ms }
// Kernel-side INT storm: Count INT commands for (DevId, EventId) pushed into the ITS command queue as fast as the ITS consumes them (no IRQL change: Windows keeps taking its interrupts).
static NTSTATUS ItsStorm(PULONG in, PULONG out)
{
    ULONG dev = in[0], ev = in[1], count = in[2], sent = 0, cw, cr, i, batch = 0;
    PHYSICAL_ADDRESS pa;
    ULONGLONG qpa;
    LARGE_INTEGER t0, t1, freq;
    if (!g_ItsRegs) {
        pa.QuadPart = 0x17140000;
        g_ItsRegs = (PUCHAR)MmMapIoSpace(pa, 0x1000, MmNonCached);
        if (!g_ItsRegs) return STATUS_INSUFFICIENT_RESOURCES;
    }
    qpa = ((ULONGLONG)READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x84)) << 32 | READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x80))) & 0x000FFFFFFFFFF000ull;
    if (!g_ItsQueue || qpa != g_ItsQueuePa) {
        if (g_ItsQueue) MmUnmapIoSpace(g_ItsQueue, 0x1000);
        pa.QuadPart = (LONGLONG)qpa;
        g_ItsQueue = (PUCHAR)MmMapIoSpace(pa, 0x1000, MmNonCached);
        g_ItsQueuePa = qpa;
        if (!g_ItsQueue) return STATUS_INSUFFICIENT_RESOURCES;
    }
    t0 = KeQueryPerformanceCounter(&freq);
    cw = READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x88));
    while (sent < count) {
        PULONG c;
        cr = READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x90));
        if (cr & 1) break;                                   // stalled: stop
        if (((cw - cr) & 0xFFF) > 0xE00) {                   // queue nearly full: let the ITS catch up
            WRITE_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x88), cw);
            continue;
        }
        c = (PULONG)(g_ItsQueue + (cw & 0xFE0));
        for (i = 0; i < 8; i++) c[i] = 0;
        c[0] = 3; c[1] = dev; c[2] = ev;
        cw = (cw + 0x20) & 0xFFF;
        sent++;
        if (++batch >= 16) { KeMemoryBarrier(); WRITE_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x88), cw); batch = 0; }
    }
    KeMemoryBarrier();
    WRITE_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x88), cw);
    t1 = KeQueryPerformanceCounter(NULL);
    out[0] = sent; out[1] = cw; out[2] = READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x90));
    out[3] = (ULONG)((ULONGLONG)(t1.QuadPart - t0.QuadPart) * 1000ull / (ULONGLONG)freq.QuadPart);
    return STATUS_SUCCESS;
}

// IOCTL_DBGCAP_HPPIR  in: { ULONG Cpu; ULONG Mode; ULONG DevId; ULONG EventId; ULONG Usec }   Mode 0 = just watch, 1 = SGI 1 to ourselves first, 2 = ITS INT(DevId,EventId)+SYNC first
//                      out: { ULONG RanOnCpu; ULONG Seen; ULONG Ids[8]; ULONG HppirBefore; ULONG Rpr; ULONG Ap1r0; ULONG Pmr; ULONG Cw; ULONG CrAfter }
// ICC_HPPIR1_EL1 reports the highest priority pending interrupt without acknowledging it and regardless of the priority mask; nothing is consumed, IRQs stay enabled (no DAIF games).
// Mode 5 (2026-10-30): "SPI window".  DevId = GICD word index (25 = INTID 800..831), EventId = bit mask.  Inside the HIGH_LEVEL window (CPU interface masked by priority, so Windows never takes it) the mask is
// written to GICD_ISENABLER[word] (virtual GICD: Gunyah enables the physical SPI when the guest does), HPPIR is watched for Usec, then ISPENDR / ISENABLER are read back into out[14] / out[15] and the SPIs are disabled
// (ICENABLER) and their pending state cleared (ICPENDR) before the IRQL drops again.  Purpose: do chip-originated MBI writes (GICD MBI frame, SPI 800..) arrive as pending SPIs in this VM?
static PUCHAR g_Gicd;
static NTSTATUS HppirProbe(PULONG in, PULONG out)
{
    ULONG cpu = in[0], mode = in[1], dev = in[2], ev = in[3], usec = in[4], seen = 0, i, cw = 0, cr = 0;
    KAFFINITY prevAff;
    KIRQL oldIrql;
    LARGE_INTEGER freq, t0, t1;
    PHYSICAL_ADDRESS pa;
    ULONGLONG qpa;

    if (mode == 2) {
        if (!g_ItsRegs) {
            pa.QuadPart = 0x17140000;
            g_ItsRegs = (PUCHAR)MmMapIoSpace(pa, 0x1000, MmNonCached);
            if (!g_ItsRegs) return STATUS_INSUFFICIENT_RESOURCES;
        }
        qpa = ((ULONGLONG)READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x84)) << 32 | READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x80))) & 0x000FFFFFFFFFF000ull;
        if (!g_ItsQueue || qpa != g_ItsQueuePa) {
            if (g_ItsQueue) MmUnmapIoSpace(g_ItsQueue, 0x1000);
            pa.QuadPart = (LONGLONG)qpa;
            g_ItsQueue = (PUCHAR)MmMapIoSpace(pa, 0x1000, MmNonCached);
            g_ItsQueuePa = qpa;
            if (!g_ItsQueue) return STATUS_INSUFFICIENT_RESOURCES;
        }
    }
    if (mode == 5 && !g_Gicd) {
        pa.QuadPart = 0x17100000;
        g_Gicd = (PUCHAR)MmMapIoSpace(pa, 0x10000, MmNonCached);
        if (!g_Gicd) return STATUS_INSUFFICIENT_RESOURCES;
    }
    if (mode == 5 && dev > 31) return STATUS_INVALID_PARAMETER;
    RtlZeroMemory(out, 16 * sizeof(ULONG));
    prevAff = KeSetSystemAffinityThreadEx((KAFFINITY)1 << cpu);
    out[0] = KeGetCurrentProcessorNumberEx(NULL);
    KeQueryPerformanceCounter(&freq);
    oldIrql = KeGetCurrentIrql();
    if (mode == 3) {                                       // MODE3: sample the CPU interface at the CALLER's irql (PASSIVE) without raising it: what does Windows leave in PMR / RPR / AP1R0 when it is just running?
        ULONGLONG k;
        out[10] = (ULONG)oldIrql;
        out[11] = (ULONG)_ReadStatusReg(ICC_RPR);
        out[12] = (ULONG)_ReadStatusReg(ICC_AP1R0);
        out[13] = (ULONG)_ReadStatusReg(ICC_PMR);
        out[14] = (ULONG)_ReadStatusReg(ARM64_SYSREG(3, 0, 12, 12, 7));       // IGRPEN1
        out[15] = (ULONG)_ReadStatusReg(ARM64_SYSREG(3, 0, 12, 12, 3));       // BPR1
        for (k = 0; k < 8; k++) out[2 + k] = 0;
        { ULONGLONG mp = (ULONGLONG)_ReadStatusReg(ARM64_SYSREG(3, 0, 0, 0, 5)); out[2] = (ULONG)mp; out[3] = (ULONG)(mp >> 32); }      // MPIDRFIX: MPIDR_EL1
        KeRevertToUserAffinityThreadEx(prevAff);
        return STATUS_SUCCESS;
    }
    KeRaiseIrql(HIGH_LEVEL, &oldIrql);
    out[10] = (ULONG)_ReadStatusReg(ICC_HPPIR1) & 0xFFFFFF;
    if (mode == 1) {
        ULONGLONG mp = (ULONGLONG)_ReadStatusReg(ARM64_SYSREG(3, 0, 0, 0, 5));
        ULONGLONG a0 = mp & 0xFF, a1 = (mp >> 8) & 0xFF, a2 = (mp >> 16) & 0xFF, a3 = (mp >> 32) & 0xFF;
        ULONGLONG v = (a3 << 48) | ((a0 >> 4) << 44) | (a2 << 32) | (1ULL << 24) | (a1 << 16) | (1ULL << (a0 & 0xF));
        _WriteStatusReg(ARM64_SYSREG(3, 0, 12, 11, 5), (__int64)v);
        __isb(_ARM64_BARRIER_SY);
    } else if (mode == 2) {
        cw = READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x88)); cr = READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x90));
        if (cw == cr) {
            PULONG c = (PULONG)(g_ItsQueue + (cw & 0xFE0));
            ULONG nxt = (cw + 0x20) & 0xFFF, nxt2 = (nxt + 0x20) & 0xFFF;
            for (i = 0; i < 8; i++) c[i] = 0;
            c[0] = 3; c[1] = dev; c[2] = ev;
            c = (PULONG)(g_ItsQueue + nxt);
            for (i = 0; i < 8; i++) c[i] = 0;
            c[0] = 5; c[4] = cpu << 16;
            KeMemoryBarrier();
            WRITE_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x88), nxt2);
        }
    } else if (mode == 5) {
        WRITE_REGISTER_ULONG((PULONG)(g_Gicd + 0x100 + 4 * dev), ev);          // GICD_ISENABLER[word] |= mask
        KeMemoryBarrier();
    }
    t0 = KeQueryPerformanceCounter(NULL);
    do {
        ULONG h = (ULONG)_ReadStatusReg(ICC_HPPIR1) & 0xFFFFFF;
        if (h != 1023) {
            ULONG k, known = 0;
            for (k = 0; k < seen && k < 8; k++) if (out[2 + k] == h) known = 1;
            if (!known && seen < 8) out[2 + seen++] = h;
        }
        t1 = KeQueryPerformanceCounter(NULL);
    } while ((ULONGLONG)(t1.QuadPart - t0.QuadPart) * 1000000ull / (ULONGLONG)freq.QuadPart < usec);
    out[11] = (ULONG)_ReadStatusReg(ICC_RPR);
    out[12] = (ULONG)_ReadStatusReg(ICC_AP1R0);
    out[13] = (ULONG)_ReadStatusReg(ICC_PMR);
    out[14] = cw;
    if (mode == 2) out[15] = READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x90));
    if (mode == 5) {
        out[14] = READ_REGISTER_ULONG((PULONG)(g_Gicd + 0x200 + 4 * dev));     // GICD_ISPENDR[word] before we clear it
        out[15] = READ_REGISTER_ULONG((PULONG)(g_Gicd + 0x100 + 4 * dev));     // GICD_ISENABLER[word] read-back
        WRITE_REGISTER_ULONG((PULONG)(g_Gicd + 0x180 + 4 * dev), ev);          // ICENABLER: disable again
        WRITE_REGISTER_ULONG((PULONG)(g_Gicd + 0x280 + 4 * dev), ev);          // ICPENDR: forget the pending state
        KeMemoryBarrier();
    }
    KeLowerIrql(oldIrql);
    KeRevertToUserAffinityThreadEx(prevAff);
    out[1] = seen;
    return STATUS_SUCCESS;
}

// IOCTL_DBGCAP_TIMING  out: { ULONG Ns[8] } nanoseconds per access for: ICC_PMR read, CNTVCT read, ICC_IAR-free HPPIR read, GICD_CTLR read, GICR0 TYPER read, ITS CTLR read, uncached DRAM read, GICR0 TYPER read again
// (TIMINGTEST) A register that a hypervisor traps and emulates costs microseconds; a real one costs about as much as an uncached DRAM read.
static NTSTATUS TimingTest(PULONG out)
{
    LARGE_INTEGER freq, t0, t1;
    KIRQL old;
    ULONG n, i, which;
    PUCHAR gicd, gicr, its;
    PHYSICAL_ADDRESS pa;
    volatile ULONG sink = 0;
    ULONGLONG sinkq = 0;
    if (!g_ItsRegs) {
        pa.QuadPart = 0x17140000;
        g_ItsRegs = (PUCHAR)MmMapIoSpace(pa, 0x1000, MmNonCached);
        if (!g_ItsRegs) return STATUS_INSUFFICIENT_RESOURCES;
    }
    if (!g_ItsQueue) {
        ULONGLONG qpa = ((ULONGLONG)READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x84)) << 32 | READ_REGISTER_ULONG((PULONG)(g_ItsRegs + 0x80))) & 0x000FFFFFFFFFF000ull;
        pa.QuadPart = (LONGLONG)qpa;
        g_ItsQueue = (PUCHAR)MmMapIoSpace(pa, 0x1000, MmNonCached);
        g_ItsQueuePa = qpa;
        if (!g_ItsQueue) return STATUS_INSUFFICIENT_RESOURCES;
    }
    its = g_ItsRegs;
    pa.QuadPart = 0x17100000; gicd = (PUCHAR)MmMapIoSpace(pa, 0x1000, MmNonCached);
    pa.QuadPart = 0x17180000; gicr = (PUCHAR)MmMapIoSpace(pa, 0x1000, MmNonCached);
    if (!gicd || !gicr) return STATUS_INSUFFICIENT_RESOURCES;
    n = 20000;
    KeQueryPerformanceCounter(&freq);
    KeRaiseIrql(DISPATCH_LEVEL, &old);
    for (which = 0; which < 11; which++) {      // TIMING2
        t0 = KeQueryPerformanceCounter(NULL);
        for (i = 0; i < n; i++) {
            switch (which) {
            case 0: sinkq += (ULONGLONG)_ReadStatusReg(ICC_PMR); break;
            case 1: sinkq += (ULONGLONG)_ReadStatusReg(ARM64_SYSREG(3, 3, 14, 0, 2)); break;
            case 2: sinkq += (ULONGLONG)_ReadStatusReg(ICC_HPPIR1); break;
            case 3: sink += READ_REGISTER_ULONG((PULONG)gicd); break;
            case 4: sink += READ_REGISTER_ULONG((PULONG)(gicr + 8)); break;
            case 5: sink += READ_REGISTER_ULONG((PULONG)its); break;
            case 6: sink += READ_REGISTER_ULONG((PULONG)g_ItsQueue); break;
            case 8: _WriteStatusReg(ARM64_SYSREG(3, 0, 12, 11, 5), (__int64)(1ULL << 24)); break;                       // SGI1R, empty target list (no-op if not trapped)
            case 9: _WriteStatusReg(ICC_PMR, _ReadStatusReg(ICC_PMR)); break;                                            // PMR write-back of the same value
            case 10: _WriteStatusReg(ARM64_SYSREG(3, 0, 12, 12, 3), _ReadStatusReg(ARM64_SYSREG(3, 0, 12, 12, 3))); break;   // BPR1 write-back
            default: sink += READ_REGISTER_ULONG((PULONG)(gicr + 8)); break;
            }
        }
        t1 = KeQueryPerformanceCounter(NULL);
        out[which] = (ULONG)((ULONGLONG)(t1.QuadPart - t0.QuadPart) * 1000000000ull / (ULONGLONG)freq.QuadPart / n);
    }
    KeLowerIrql(old);
    MmUnmapIoSpace(gicd, 0x1000);
    MmUnmapIoSpace(gicr, 0x1000);
    out[11] = (ULONG)sink ^ (ULONG)sinkq;
    return STATUS_SUCCESS;
}


// ---- breadcrumbs in Android's ramoops region (0xD7E00000, 2 MiB, one console zone) --------------------------------------------------------------------------------------------------
// The text lands in a persistent_ram buffer ({sig 'DBGC', start, size, data...}); after the next (warm) reset Android shows it as /sys/fs/pstore/console-ramoops-0, even when Windows hung and never wrote anything to disk.
// Only the first 1 MiB is used: 0xD7FF1000.. holds MuChain's battery data and the ITS level-2 page pool.
#define CRUMB_PA 0xD7F00000ull          // second half of the ramoops region; Android's console log starts at 0xD7E00000 and normally does not reach this far
#define CRUMB_MAX 0xE0000u
#define CRUMB_SIG 0x4D524350u            // 'PCRM'
static PUCHAR g_Crumb;
static ULONG g_CrumbPos;
static PUCHAR g_PrevCrumb;
static ULONG g_PrevLen;
static KSPIN_LOCK g_CrumbLock;

static VOID CrumbPut(const char *p, ULONG n)
{
    KIRQL old; ULONG i;
    if (!g_Crumb) return;
    KeAcquireSpinLock(&g_CrumbLock, &old);
    if (g_CrumbPos + n <= CRUMB_MAX) {
        for (i = 0; i < n; i++) g_Crumb[12 + g_CrumbPos + i] = (UCHAR)p[i];
        g_CrumbPos += n;
        KeMemoryBarrier();
        ((PULONG)g_Crumb)[1] = g_CrumbPos;      // start
        ((PULONG)g_Crumb)[2] = g_CrumbPos;      // size
        KeMemoryBarrier();
    }
    KeReleaseSpinLock(&g_CrumbLock, old);
}

static VOID CrumbHex(char *d, ULONGLONG v, int digits)
{
    int q;
    for (q = 0; q < digits; q++) d[q] = Hex[(v >> (4 * (digits - 1 - q))) & 15];
}

// "<tag> <a> <b>\n"
static VOID CrumbLine(const char *tag, ULONGLONG a, ULONGLONG b)
{
    char buf[96]; ULONG n = 0;
    while (*tag && n < 40) buf[n++] = *tag++;
    buf[n++] = ' '; CrumbHex(buf + n, a, 8); n += 8;
    buf[n++] = ' '; CrumbHex(buf + n, b, 8); n += 8;
    buf[n++] = '\n';
    CrumbPut(buf, n);
}

static VOID CrumbText(const char *prefix, PCUNICODE_STRING us, ULONGLONG a)
{
    char buf[160]; ULONG n = 0, i;
    while (*prefix && n < 20) buf[n++] = *prefix++;
    buf[n++] = ' '; CrumbHex(buf + n, a, 4); n += 4; buf[n++] = ' ';
    if (us && us->Buffer) {
        ULONG len = us->Length / 2;
        ULONG from = len > 90 ? len - 90 : 0;                // keep the end of the path
        for (i = from; i < len && n < 150; i++) { WCHAR c = us->Buffer[i]; buf[n++] = (c >= 32 && c < 127) ? (char)c : '?'; }
    }
    buf[n++] = '\n';
    CrumbPut(buf, n);
}

// ---- bug check marker -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// Runs at HIGH_LEVEL when the kernel bug-checks: no lock, no pool, no paged memory.  It leaves "BUGCHECK cpu irql time" plus the raw stack above its own frame (KeBugCheckEx's CONTEXT with the
// code/parameters in x0..x4 sits there) in the persistent crumb text, so that the next boot's pstore shows whether the stop was a bug check at all (no marker = hard hang / watchdog reset).
static KBUGCHECK_CALLBACK_RECORD g_BcRec;
static UCHAR g_BcBuf[16];
static volatile LONG g_BcOnce;
static BOOLEAN g_BcReg;

static VOID CrumbPutRaw(const char *p, ULONG n)
{
    ULONG i;
    if (!g_Crumb || g_CrumbPos + n > CRUMB_MAX) return;
    for (i = 0; i < n; i++) g_Crumb[12 + g_CrumbPos + i] = (UCHAR)p[i];
    g_CrumbPos += n;
    KeMemoryBarrier();
    ((PULONG)g_Crumb)[1] = g_CrumbPos;
    ((PULONG)g_Crumb)[2] = g_CrumbPos;
    KeMemoryBarrier();
}

static VOID CrumbHexRaw(char *d, ULONGLONG v, int digits)
{
    int q;
    for (q = 0; q < digits; q++) d[q] = Hex[(v >> (4 * (digits - 1 - q))) & 15];
}

static VOID BugCheckCb(PVOID Buffer, ULONG Length)
{
    char b[96]; ULONG n = 0, w;
    volatile ULONG_PTR here;
    ULONG_PTR lo = 0, hi = 0, p, end;
    UNREFERENCED_PARAMETER(Buffer); UNREFERENCED_PARAMETER(Length);
    if (g_BcOnce) return;                                    // only the first invocation (other CPUs are already stopped)
    g_BcOnce = 1;
    here = (ULONG_PTR)&here;
    memcpy(b, "BUGCHECK cpu ", 13); n = 13;
    CrumbHexRaw(b + n, KeGetCurrentProcessorNumber(), 4); n += 4;
    memcpy(b + n, " irql ", 6); n += 6;
    CrumbHexRaw(b + n, KeGetCurrentIrql(), 2); n += 2;
    memcpy(b + n, " ms ", 4); n += 4;
    CrumbHexRaw(b + n, KeQueryInterruptTime() / 10000, 8); n += 8;
    b[n++] = '\n';
    CrumbPutRaw(b, n);
    IoGetStackLimits(&lo, &hi);
    p = here & ~(ULONG_PTR)7;
    if (here >= lo && here < hi) end = hi; else end = (p | 0xFFF) + 1;
    if (end > p + 3072) end = p + 3072;
    // "S <addr16> <w0> <w1> <w2> <w3>\n" per 32 bytes
    for (; p + 32 <= end; p += 32) {
        n = 0; b[n++] = 'S'; b[n++] = ' ';
        CrumbHexRaw(b + n, p, 16); n += 16;
        for (w = 0; w < 4; w++) { b[n++] = ' '; CrumbHexRaw(b + n, *(volatile ULONGLONG *)(p + 8 * w), 16); n += 16; }
        b[n++] = '\n';
        CrumbPutRaw(b, n);
    }
    CrumbPutRaw("BUGCHECK end\n", 13);
}

static VOID CrumbImageNotify(PUNICODE_STRING Name, HANDLE Pid, PIMAGE_INFO Info)
{
    UNREFERENCED_PARAMETER(Info);
    if (Pid == NULL) { CrumbText("drv", Name, 0); return; }          // kernel-mode image
    if (Name && Name->Buffer && Name->Length >= 8) {                  // user-mode: only the executables
        PWCHAR e = Name->Buffer + Name->Length / 2 - 4;
        if (e[0] == L'.' && (e[1] | 0x20) == L'e' && (e[2] | 0x20) == L'x' && (e[3] | 0x20) == L'e') CrumbText("exe", Name, (ULONGLONG)(ULONG_PTR)Pid);
    }
}

static HANDLE g_CrumbThread;
static PETHREAD g_CrumbThreadObj;
static volatile LONG g_CrumbOn;
static PUCHAR g_CrumbIts;


// ---- breadcrumbs also go to a preallocated file on the Windows volume (C:\rm9\crumb.bin, created by run.cmd) with write-through, so a hang that loses DRAM still leaves the text on disk ------------
NTSYSAPI NTSTATUS NTAPI ZwFlushBuffersFile(HANDLE FileHandle, PIO_STATUS_BLOCK IoStatusBlock);
static HANDLE g_CrumbFile;
static ULONG g_CrumbDisk;                 // bytes of the crumb text already written to the file
static WCHAR g_CrumbPath[160];

static BOOLEAN CrumbResolvePath(VOID)
{
    UNICODE_STRING link = RTL_CONSTANT_STRING(L"\\SystemRoot");
    OBJECT_ATTRIBUTES oa; HANDLE h; UNICODE_STRING tgt; WCHAR buf[128]; ULONG len = 0, i;
    InitializeObjectAttributes(&oa, &link, OBJ_KERNEL_HANDLE | OBJ_CASE_INSENSITIVE, NULL, NULL);
    if (!NT_SUCCESS(ZwOpenSymbolicLinkObject(&h, GENERIC_READ, &oa))) return FALSE;
    tgt.Buffer = buf; tgt.Length = 0; tgt.MaximumLength = sizeof(buf);
    if (!NT_SUCCESS(ZwQuerySymbolicLinkObject(h, &tgt, &len))) { ZwClose(h); return FALSE; }
    ZwClose(h);
    // "\Device\HarddiskVolumeN\Windows" -> "\Device\HarddiskVolumeN\rm9\crumb.bin"
    len = tgt.Length / 2;
    for (i = len; i > 0 && buf[i - 1] != L'\\'; i--) ;
    if (i == 0 || i + 20 > 150) return FALSE;
    RtlCopyMemory(g_CrumbPath, buf, i * 2);
    RtlCopyMemory(g_CrumbPath + i, L"rm9\\crumb.bin", sizeof(L"rm9\\crumb.bin"));
    return TRUE;
}

static VOID CrumbDiskFlush(VOID)
{
    return;                    // disabled: the write-through kernel thread can deadlock with the file system (it froze Windows); the DRAM breadcrumbs stay
    if (!g_CrumbFile) {
        UNICODE_STRING nm; OBJECT_ATTRIBUTES oa; IO_STATUS_BLOCK io;
        if (!g_CrumbPath[0] && !CrumbResolvePath()) return;
        RtlInitUnicodeString(&nm, g_CrumbPath);
        InitializeObjectAttributes(&oa, &nm, OBJ_KERNEL_HANDLE | OBJ_CASE_INSENSITIVE, NULL, NULL);
        if (!NT_SUCCESS(ZwCreateFile(&g_CrumbFile, GENERIC_READ | GENERIC_WRITE | SYNCHRONIZE, &oa, &io, NULL, FILE_ATTRIBUTE_NORMAL, FILE_SHARE_READ | FILE_SHARE_WRITE, FILE_OPEN,
                                     FILE_NON_DIRECTORY_FILE | FILE_SYNCHRONOUS_IO_NONALERT | FILE_WRITE_THROUGH, NULL, 0))) { g_CrumbFile = NULL; return; }
        CrumbPut("crumb file open\n", 15);
    }
    if (g_CrumbPos > g_CrumbDisk) {
        IO_STATUS_BLOCK io; LARGE_INTEGER off;
        ULONG from = g_CrumbDisk & ~0x1FFu, to = g_CrumbPos;
        if (to - from > 0x8000) to = from + 0x8000;
        off.QuadPart = from;
        if (NT_SUCCESS(ZwWriteFile(g_CrumbFile, NULL, NULL, NULL, &io, g_Crumb + 12 + from, to - from, &off, NULL))) {
            ZwFlushBuffersFile(g_CrumbFile, &io);
            g_CrumbDisk = to;
        }
    }
}

// ---- hang / overheat guard ----------------------------------------------------------------------------------------------------------------------------------------------------------------------
// MuChain's LONGRUN mode disables the GH watchdog at ExitBootServices, so a frozen Windows (or a runaway one with no FxPPM thermal control) stays on and heats the phone indefinitely.
// Once loaded, this driver re-enables the watchdog (timeout set earlier by Mu's SEC, ~31 s) and pings it every second from the crumb thread, but only while the hottest TSENS sensor is below
// TEMP_LIMIT_DC.  If Windows freezes, or the temperature passes the limit, the pings stop and the hypervisor resets the phone within the timeout.  Flag file/registry not needed: any failure to
// enable leaves the watchdog off exactly as before.
#define TEMP_LIMIT_DC 1000                                   // 100.0 C in 0.1 C units, on the maximum of the last TEMP_WIN seconds
#define TEMP_WIN 8                                           // TSENS samples come and go (an invalid sample reads 0), so one second's maximum swings by 40 C; idle Windows without FxPPM reaches 85-94 C
ULONGLONG GhSmc(ULONGLONG fn, ULONGLONG a1, ULONGLONG a2, ULONGLONG a3);   // smc.asm
#define GH_WDT_CONTROL 0x86000005u
#define GH_WDT_PING 0x86000007u
static PUCHAR g_Ts[3];
static const ULONG g_TsBase[3] = { 0x0C228000u, 0x0C229000u, 0x0C22A000u };
static const ULONG g_TsN[3] = { 15, 16, 13 };
static BOOLEAN g_WdtGuard;
static volatile ULONG g_WdtDiag[6];                                   // [0] bit mask of mapped TSENS blocks, [1] hottest 0.1 C at start (0x7FFFFFFF = none), [2] ENABLE result, [3] PING result (0xFFFFFFFF = not tried)
static LONG g_MaxTempDc;                                     // last hottest valid sensor, 0.1 C
static LONG g_BlkMax[3];
static ULONG g_MaxRunSec;                                    // Services\dbgcap\MaxRunSec (guard.cmd 5th argument): experiments only - after this many seconds of guard time the watchdog is no longer pinged, whatever the state (2026-10-29: a Windows restart stuck at 'Restarting' for minutes: the DPC check cannot see that)
static volatile LONG g_TempLimit = TEMP_LIMIT_DC;          // IOCTL_DBGCAP_WDTTEST can lower it for a test (proves that a hot SoC really makes the phone reset)
static LONG g_TempWin[8] = { -2000, -2000, -2000, -2000, -2000, -2000, -2000, -2000 };                                     // per TSENS block
static volatile LONG g_WdtTestStop;                          // IOCTL_DBGCAP_WDTTEST: stop pinging on purpose (proves the reset really happens)

// Every online CPU of group 0 must run a 500 ms timer DPC; if one stops (hung with interrupts off), the pings stop too.
#define BEAT_MAX 16
#define BEAT_STALE_LIMIT 10                                  // ticks (seconds) without progress
static KDPC g_BeatDpc[BEAT_MAX];
static KTIMER g_BeatTmr[BEAT_MAX];
static volatile ULONG g_Beat[BEAT_MAX];
static ULONG g_BeatSeen[BEAT_MAX];
static ULONG g_BeatStale[BEAT_MAX];
static ULONG g_BeatN;

static VOID BeatDpcRoutine(PKDPC Dpc, PVOID Ctx, PVOID A1, PVOID A2)
{
    UNREFERENCED_PARAMETER(Dpc); UNREFERENCED_PARAMETER(A1); UNREFERENCED_PARAMETER(A2);
    g_Beat[(ULONG)(ULONG_PTR)Ctx]++;
}

static VOID BeatStart(VOID)
{
    ULONG i; LARGE_INTEGER due;
    g_BeatN = KeQueryActiveProcessorCountEx(0);
    if (g_BeatN > BEAT_MAX) g_BeatN = BEAT_MAX;
    due.QuadPart = -5000000LL;
    for (i = 0; i < g_BeatN; i++) {
        PROCESSOR_NUMBER pn; pn.Group = 0; pn.Number = (UCHAR)i; pn.Reserved = 0;
        KeInitializeDpc(&g_BeatDpc[i], BeatDpcRoutine, (PVOID)(ULONG_PTR)i);
        KeSetTargetProcessorDpcEx(&g_BeatDpc[i], &pn);
        KeInitializeTimerEx(&g_BeatTmr[i], SynchronizationTimer);
        KeSetTimerEx(&g_BeatTmr[i], due, 500, &g_BeatDpc[i]);
    }
}

static VOID BeatStop(VOID)
{
    ULONG i;
    for (i = 0; i < g_BeatN; i++) KeCancelTimer(&g_BeatTmr[i]);
    KeFlushQueuedDpcs();
    g_BeatN = 0;
}

// TRUE if every CPU made progress within BEAT_STALE_LIMIT ticks
static BOOLEAN BeatAllAlive(ULONG sec)
{
    ULONG i; BOOLEAN ok = TRUE;
    for (i = 0; i < g_BeatN; i++) {
        ULONG b = g_Beat[i];
        if (b != g_BeatSeen[i]) { g_BeatSeen[i] = b; g_BeatStale[i] = 0; }
        else if (++g_BeatStale[i] >= BEAT_STALE_LIMIT) {
            ok = FALSE;
            if (g_BeatStale[i] == BEAT_STALE_LIMIT) CrumbLine("wdtguard CPU STALE cpu/sec", i, sec);
        }
    }
    return ok;
}

static LONG HottestDc(VOID)
{
    LONG best = -2000; ULONG b, n;
    for (b = 0; b < 3; b++) {
        LONG bb = -2000;
        if (!g_Ts[b]) continue;
        for (n = 0; n < g_TsN[b]; n++) {
            ULONG v = READ_REGISTER_ULONG((PULONG)(g_Ts[b] + 0xA0 + 4 * n));
            LONG t;
            if (!(v & (1u << 21))) continue;
            t = (LONG)(v & 0xFFF); if (t & 0x800) t -= 0x1000;
            if (t > bb) bb = t;
        }
        g_BlkMax[b] = bb;
        if (bb > best) best = bb;
    }
    return best;
}

// ---- battery temperature (2026-10-31) ------------------------------------------------------------------------------------------------------------------------------------------------------------
// battlive.ps1 keeps the ADSP battmgr values in the RAM block at 0xD7FF1000 ('BATT', count, then {key, value} pairs; key 0x30000C = battery temperature in 0.01 C).  It is read once a second, read-only.
// Limits (Li-ion: charging should not go on above ~45 C; phones start throttling at 40-43 C): the governor's budget shrinks from 40 C to zero at 46 C; the static cap drops to the lowest state at 45 C;
// and 48 C for BATT_STOP_SEC seconds in a row stops the watchdog pings = the phone resets and Android's own charger thermal control takes over.  Readings outside -10..80 C are ignored.
#define BATT_PA        0xD7FF1000ull
#define BATT_NONE      (-32768)
#define BATT_STOP_CD   4800                                   // default; Services\dbgcap\BattStop (0.01 C, 2000..6000) overrides it - set it below the present temperature to prove the stop
#define BATT_STOP_SEC  10
static PUCHAR g_Batt;
static volatile LONG g_BattCd = BATT_NONE;                   // 0.01 C, BATT_NONE = no valid reading
static volatile LONG g_BattHot;                              // seconds in a row at or above g_BattStop
static LONG g_BattStop = BATT_STOP_CD;

static LONG BattReadCd(VOID)
{
    ULONG i, n;
    if (!g_Batt) return BATT_NONE;
    if (READ_REGISTER_ULONG((PULONG)g_Batt) != 0x54544142u) return BATT_NONE;
    n = READ_REGISTER_ULONG((PULONG)(g_Batt + 4)); if (n > 24) n = 24;
    for (i = 0; i < n; i++) {
        if (READ_REGISTER_ULONG((PULONG)(g_Batt + 8 + 8 * i)) == 0x30000Cu) {
            LONG v = (LONG)READ_REGISTER_ULONG((PULONG)(g_Batt + 12 + 8 * i));
            return (v >= -1000 && v <= 8000) ? v : BATT_NONE;
        }
    }
    return BATT_NONE;
}

static VOID WdtGuardStart(VOID)
{
    PHYSICAL_ADDRESS pa; ULONG b; unsigned int r1, r2;
    g_WdtDiag[2] = g_WdtDiag[3] = 0xFFFFFFFFu;
    for (b = 0; b < 3; b++) { pa.QuadPart = g_TsBase[b]; g_Ts[b] = (PUCHAR)MmMapIoSpace(pa, 0x1000, MmNonCached); if (g_Ts[b]) g_WdtDiag[0] |= 1u << b; }
    { PHYSICAL_ADDRESS bpa; bpa.QuadPart = (LONGLONG)BATT_PA; g_Batt = (PUCHAR)MmMapIoSpace(bpa, 0x100, MmNonCached); }
    g_WdtDiag[1] = (ULONG)HottestDc();
    if ((LONG)g_WdtDiag[1] == -2000) { g_WdtDiag[1] = 0x7FFFFFFFu; CrumbPut("wdtguard: no TSENS, guard off\n", 30); return; }   // never arm the watchdog blind
    GhSmc(GH_WDT_CONTROL, 2u, 0, 0);                          // DISABLE first (result ignored): MuChain's keep-alive leaves the watchdog armed, LONGRUN's old mode leaves it off; ENABLE below restarts the timeout either way
    r1 = (unsigned int)GhSmc(GH_WDT_CONTROL, 3u, 0, 0);       // ENABLE
    g_WdtDiag[2] = r1;
    r2 = (unsigned int)GhSmc(GH_WDT_PING, 0, 0, 0);
    g_WdtDiag[3] = r2;
    if (r1 == 0 && r2 == 0) { g_WdtGuard = TRUE; BeatStart(); CrumbPut("wdtguard: ON\n", 13); }
    else { GhSmc(GH_WDT_CONTROL, 2u, 0, 0); CrumbLine("wdtguard FAIL en/ping", r1, r2); }      // back out: DISABLE
}

static VOID WdtGuardTick(ULONG sec)
{
    LONG t; BOOLEAN alive, cool;
    if (!g_WdtGuard) return;
    t = HottestDc();
    g_TempWin[sec % TEMP_WIN] = t;
    { ULONG w; for (w = 0; w < TEMP_WIN; w++) if (g_TempWin[w] > t) t = g_TempWin[w]; }      // windowed maximum
    g_MaxTempDc = t;
    alive = BeatAllAlive(sec);
    {   // battery: log every 5 s, count the seconds at the hard limit
        LONG bc = BattReadCd();
        g_BattCd = bc;
        if (bc != BATT_NONE && bc >= g_BattStop) g_BattHot++; else g_BattHot = 0;
        if ((sec % 5) == 0 && bc != BATT_NONE) CrumbLine("battery cC/hotsec", (ULONG)bc, (ULONG)g_BattHot);
    }
    cool = (t > -1000) && (t < g_TempLimit) && (g_BattHot < BATT_STOP_SEC);                  // fail-safe: eight seconds without ONE valid TSENS sample (window maximum = -200 C) counts as 'too hot' - never ping blind
    if ((sec % 5) == 0) {                                     // temperatures every 5 s: overall, then per TSENS block (0.1 C, signed)
        char b[96]; ULONG n = 0, q;
        memcpy(b, "temp ", 5); n = 5;
        CrumbHexRaw(b + n, (ULONG)t & 0xFFFF, 4); n += 4;
        for (q = 0; q < 3; q++) { b[n++] = ' '; CrumbHexRaw(b + n, (ULONG)g_BlkMax[q] & 0xFFFF, 4); n += 4; }
        b[n++] = '\n';
        CrumbPut(b, n);
    }
    if (!cool) { if ((sec % 5) == 0) { if (g_BattHot >= BATT_STOP_SEC) CrumbLine("wdtguard BATTERY HOT: no ping cC/sec", (ULONG)g_BattCd, sec); else CrumbLine("wdtguard HOT: no ping dC/sec", (ULONG)t, sec); } return; }
    if (g_MaxRunSec && sec > g_MaxRunSec) { if ((sec % 5) == 0) CrumbLine("wdtguard MAXRUN: no ping sec/max", sec, g_MaxRunSec); return; }
    if (!alive || g_WdtTestStop) return;
    GhSmc(GH_WDT_PING, 0, 0, 0);
}

// ---- CPU frequency cap ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
// Windows on this phone has no working processor power manager (FxPPM fails to load), so every CPU cluster stays at the boot-time maximum and an idle-but-busy Windows sits at 85-94 C.  The EPSS cpufreq-hw
// domains take the desired performance-state index at +0x320 (what Linux's qcom-cpufreq-hw writes); a value written here holds (verified 2026-10-27: 4 min, re-asserted every 3 s).  We write the capped index
// once a second and the lowest state when the temperature is high.  Lost on reboot.  Order of the domains matches Android: dom0 cpu0-1, dom1 cpu5-6, dom2 cpu7, dom3 cpu2-4.
static const ULONG g_EpBase[4] = { 0x17D91000u, 0x17D92000u, 0x17D93000u, 0x17D94000u };
static const ULONG g_EpTargetMhz[4] = { 1344, 1498, 1478, 1498 };
static PUCHAR g_Ep[4];
static ULONG g_EpIdx[4];
static BOOLEAN g_EpOn;

static BOOLEAN g_NoCap;

static VOID CapStart(VOID)
{
    PHYSICAL_ADDRESS pa; ULONG d, i;
    if (g_NoCap) { CrumbPut("cap: NoCap set, clusters left alone\n", 36); return; }
    for (d = 0; d < 4; d++) {
        ULONG best = 0, bd = 0xFFFFFFFFu;
        pa.QuadPart = g_EpBase[d]; g_Ep[d] = (PUCHAR)MmMapIoSpace(pa, 0x1000, MmNonCached);
        if (!g_Ep[d]) { CrumbLine("cap: map failed dom", d, 0); return; }
        for (i = 0; i < 40; i++) {
            ULONG lv = READ_REGISTER_ULONG((PULONG)(g_Ep[d] + 0x100 + 4 * i)) & 0xFF, m, dd;
            if (lv == 0) break;
            m = (lv * 192) / 10;
            dd = (m > g_EpTargetMhz[d]) ? m - g_EpTargetMhz[d] : g_EpTargetMhz[d] - m;
            if (dd < bd) { bd = dd; best = i; }
        }
        g_EpIdx[d] = best;
    }
    g_EpOn = TRUE;
    CrumbLine("cap: idx d0/d1", g_EpIdx[0], g_EpIdx[1]);
    CrumbLine("cap: idx d2/d3", g_EpIdx[2], g_EpIdx[3]);
}

static VOID CapTick(BOOLEAN hot)
{
    ULONG d;
    if (!g_EpOn) return;
    for (d = 0; d < 4; d++) WRITE_REGISTER_ULONG((PULONG)(g_Ep[d] + 0x320), hot ? 0u : g_EpIdx[d]);
}

// ---- CPU frequency governor (2026-10-31) ---------------------------------------------------------------------------------------------------------------------------------------------------------
// The static cap above keeps the phone cool but also slow.  With Services\dbgcap\Gov = 1 (or IOCTL_DBGCAP_GOV mode 1) a thread samples the per-CPU idle time every GOV_PERIOD_MS (ZwQuerySystemInformation,
// SystemProcessorPerformanceInformation) and moves every EPSS domain between its lowest and highest performance state like an ondemand/schedutil governor: >= 80 % busy -> the ceiling at once; otherwise
// the lowest state that keeps the load at about 60 %; down after three quiet samples; the jump to the ceiling needs two consecutive busy samples (one busy sample only scales the frequency by 1/0.6).
// The ceiling is a thermal budget B (0.1 % of each domain's state range) steered by the fast hottest-TSENS reading: above 70 C (GovTemp) it drops by 2 % + 0.5 % per degree every sample, at 90 C it is zero, below 65 C it
// recovers 1 % per sample (70..65 C hold).  Only active while the watchdog guard has valid temperatures; CapTick takes over again whenever this thread is not ticking.
#define GOV_PERIOD_MS 100
#define GOV_MAXCPU    16
typedef NTSTATUS (NTAPI *PFN_ZWQSI)(ULONG Class, PVOID Buf, ULONG Len, PULONG Ret);
typedef struct { LONGLONG Idle, Kernel, User, Dpc, Intr; ULONG IntCnt, Pad; } GOV_PERF;     // SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION (48 bytes); Kernel includes Idle
static const ULONG g_GovMask[4] = { 0x03u, 0x60u, 0x80u, 0x1Cu };                          // domain -> CPUs (Android numbering = MADT order): dom0 cpu0-1, dom1 cpu5-6, dom2 cpu7, dom3 cpu2-4
static ULONG g_GovF[4][40];                                                                // MHz per performance state (EPSS LUT low byte x 19.2)
static ULONG g_GovN[4];
static volatile LONG g_GovOn, g_GovStopReq, g_GovTicks;
static BOOLEAN g_GovWanted;
static HANDLE g_GovThrH;
static PKTHREAD g_GovThr;
static ULONG g_GovIdx[4], g_GovCeil[4], g_GovUtil[4], g_GovLow[4], g_GovHigh[4], g_GovBusy[GOV_MAXCPU], g_GovB = 1000, g_GovBcap = 1000, g_GovStat, g_GovErr, g_GovUps, g_GovCpus;
static LONG g_GovT, g_GovTring[3];
static LONG g_GovHot = 700;                                                // 0.1 C: the budget starts to shrink above this (Services\dbgcap\GovTemp, 500..850), recovers below this - 5 C

static VOID GovThread(PVOID Ctx)
{
    UNICODE_STRING nm = RTL_CONSTANT_STRING(L"ZwQuerySystemInformation");
    PFN_ZWQSI q = (PFN_ZWQSI)MmGetSystemRoutineAddress(&nm);
    GOV_PERF *pi = (GOV_PERF *)ExAllocatePoolWithTag(NonPagedPool, sizeof(GOV_PERF) * GOV_MAXCPU, 'vogD');
    LONGLONG pIdle[GOV_MAXCPU], pTot[GOV_MAXCPU];
    LARGE_INTEGER dl; BOOLEAN have = FALSE; ULONG i, d;
    UNREFERENCED_PARAMETER(Ctx);
    dl.QuadPart = -10000LL * GOV_PERIOD_MS;
    if (!q || !pi) { g_GovOn = 0; CrumbLine("gov: no ZwQuerySystemInformation / pool", q ? 1u : 0u, pi ? 1u : 0u); if (pi) ExFreePoolWithTag(pi, 'vogD'); PsTerminateSystemThread(STATUS_SUCCESS); return; }
    KeSetPriorityThread(KeGetCurrentThread(), 16);
    while (!g_GovStopReq) {
        ULONG ret = 0, ncpu, tick; NTSTATUS st; LONG temp;
        KeDelayExecutionThread(KernelMode, FALSE, &dl);
        if (g_GovStopReq) break;
        if (!g_GovOn || !g_EpOn || !g_WdtGuard) { have = FALSE; continue; }       // never raise a ceiling blind: needs the TSENS guard
        st = q(8, pi, (ULONG)(sizeof(GOV_PERF) * GOV_MAXCPU), &ret);
        g_GovStat = (ULONG)st;
        if (!NT_SUCCESS(st)) { g_GovErr++; have = FALSE; continue; }
        ncpu = ret / (ULONG)sizeof(GOV_PERF); if (ncpu > GOV_MAXCPU) ncpu = GOV_MAXCPU;
        g_GovCpus = ncpu;
        for (i = 0; i < ncpu; i++) {
            LONGLONG tot = pi[i].Kernel + pi[i].User;
            if (have) {
                LONGLONG dt = tot - pTot[i], di = pi[i].Idle - pIdle[i];
                ULONG b = 0;
                if (dt > 0) { if (di < 0) di = 0; if (di > dt) di = dt; b = (ULONG)(1000 - (di * 1000) / dt); }
                g_GovBusy[i] = b;
            }
            pTot[i] = tot; pIdle[i] = pi[i].Idle;
        }
        if (!have) { have = TRUE; continue; }
        tick = (ULONG)(++g_GovTicks);           // single writer
        temp = HottestDc();                     // fast reading (0.1 C); -2000 = no valid sample this time
        if (temp < -1000) temp = g_MaxTempDc;
        g_GovTring[tick % 3] = temp; g_GovT = temp;
        { ULONG r; for (r = 0; r < 3; r++) if (g_GovTring[r] > temp) temp = g_GovTring[r]; }       // maximum of the last three samples
        {   // battery limit on the budget: none below 40 C, linear down to zero at 46 C
            LONG bc = g_BattCd; ULONG cap = 1000;
            if (bc != BATT_NONE) { if (bc >= 4600) cap = 0; else if (bc > 4000) cap = (ULONG)(((4600 - bc) * 1000) / 600); }
            g_GovBcap = cap;
        }
        if (temp >= 900) g_GovB = 0;
        else if (temp > g_GovHot) { ULONG dec = 20 + (ULONG)(temp - g_GovHot) / 2; g_GovB = (g_GovB > dec) ? g_GovB - dec : 0; }
        else if (temp < g_GovHot - 50) { g_GovB += 10; if (g_GovB > 1000) g_GovB = 1000; }
        for (d = 0; d < 4; d++) {
            ULONG n = g_GovN[d], ceil, util = 0, cur, want, c;
            if (n == 0) continue;
            ceil = ((g_GovB < g_GovBcap ? g_GovB : g_GovBcap) * (n - 1) + 500) / 1000;
            if (ceil > n - 1) ceil = n - 1;
            for (c = 0; c < ncpu; c++) if ((g_GovMask[d] >> c) & 1u) if (g_GovBusy[c] > util) util = g_GovBusy[c];
            cur = g_GovIdx[d]; if (cur > n - 1) cur = n - 1;
            g_GovHigh[d] = (util >= 800) ? g_GovHigh[d] + 1 : 0;
            if (util >= 800 && g_GovHigh[d] >= 2) want = ceil;                   // second busy sample in a row: the ceiling at once
            else {
                ULONGLONG need = ((ULONGLONG)g_GovF[d][cur] * util) / 600u;
                for (want = 0; want < n - 1 && g_GovF[d][want] < need; want++) { }
            }
            if (want > ceil) want = ceil;
            if (want > cur) { cur = want; g_GovLow[d] = 0; g_GovUps++; }
            else if (want < cur) { if (++g_GovLow[d] >= 3) { cur = want; g_GovLow[d] = 0; } }
            else g_GovLow[d] = 0;
            if (cur > ceil) cur = ceil;
            g_GovUtil[d] = util; g_GovCeil[d] = ceil;
            if (cur != g_GovIdx[d] || (tick % 10) == 0) WRITE_REGISTER_ULONG((PULONG)(g_Ep[d] + 0x320), cur);
            g_GovIdx[d] = cur;
        }
    }
    ExFreePoolWithTag(pi, 'vogD');
    PsTerminateSystemThread(STATUS_SUCCESS);
}

static NTSTATUS GovStart(VOID)
{
    OBJECT_ATTRIBUTES oa; NTSTATUS st; ULONG d, i;
    if (g_GovThr) { g_GovOn = 1; return STATUS_SUCCESS; }
    if (!g_EpOn) return STATUS_UNSUCCESSFUL;
    for (d = 0; d < 4; d++) {
        for (i = 0; i < 40; i++) {
            ULONG lv = READ_REGISTER_ULONG((PULONG)(g_Ep[d] + 0x100 + 4 * i)) & 0xFF;
            if (lv == 0) break;
            g_GovF[d][i] = (lv * 192) / 10;
        }
        g_GovN[d] = i; g_GovIdx[d] = (g_EpIdx[d] < i) ? g_EpIdx[d] : (i ? i - 1 : 0); g_GovCeil[d] = g_GovIdx[d]; g_GovLow[d] = 0;
    }
    g_GovB = 1000; g_GovStopReq = 0; g_GovTicks = 0; g_GovErr = 0; g_GovUps = 0;
    InitializeObjectAttributes(&oa, NULL, OBJ_KERNEL_HANDLE, NULL, NULL);
    g_GovOn = 1;
    st = PsCreateSystemThread(&g_GovThrH, THREAD_ALL_ACCESS, &oa, NULL, NULL, GovThread, NULL);
    if (!NT_SUCCESS(st)) { g_GovOn = 0; CrumbLine("gov: thread failed", (ULONG)st, 0); return st; }
    st = ObReferenceObjectByHandle(g_GovThrH, THREAD_ALL_ACCESS, *PsThreadType, KernelMode, (PVOID *)&g_GovThr, NULL);
    ZwClose(g_GovThrH); g_GovThrH = NULL;
    if (!NT_SUCCESS(st)) { g_GovStopReq = 1; g_GovOn = 0; }
    CrumbLine("gov: started n d0/d1", g_GovN[0], g_GovN[1]);
    CrumbLine("gov: started n d2/d3", g_GovN[2], g_GovN[3]);
    return st;
}

static VOID GovStop(VOID)
{
    g_GovOn = 0; g_GovStopReq = 1;
    if (g_GovThr) { KeWaitForSingleObject(g_GovThr, Executive, KernelMode, FALSE, NULL); ObDereferenceObject(g_GovThr); g_GovThr = NULL; }
}

static VOID CrumbThread(PVOID Ctx)
{
    LARGE_INTEGER d; ULONG sec = 0; ULONG govPrev = 0;
    UNREFERENCED_PARAMETER(Ctx);
    g_WdtDiag[4] = 1;                                        // stage: thread entered
    KeSetSystemAffinityThreadEx((KAFFINITY)8);               // CPU 3 if it exists
    g_WdtDiag[4] = 2;
    d.QuadPart = -10000000LL;                                // 1 s
    WdtGuardStart();
    CapStart();
    if (g_GovWanted) GovStart();
    g_WdtDiag[4] = 3;                                        // stage: WdtGuardStart returned
    while (g_CrumbOn) {
        g_WdtDiag[5] = sec;
        WdtGuardTick(sec);
        {   // the governor owns the EPSS registers while its thread ticks; otherwise (off, stuck, no valid temperature) the static cap is written
            ULONG gt = (ULONG)g_GovTicks;
            BOOLEAN govAlive = (g_GovOn != 0) && (gt != govPrev);
            govPrev = gt;
            if (!govAlive) CapTick((BOOLEAN)((g_MaxTempDc >= 950) || (g_BattCd != BATT_NONE && g_BattCd >= 4500)));       // windowed hottest sensor, 0.1 C: drop to the lowest state above 95 C
            else if ((sec % 5) == 0) { CrumbLine("gov idx d0/d1", g_GovIdx[0], g_GovIdx[1]); CrumbLine("gov idx d2/d3", g_GovIdx[2], g_GovIdx[3]); }
        }
        ULONG cr = g_CrumbIts ? READ_REGISTER_ULONG((PULONG)(g_CrumbIts + 0x90)) : 0xFFFFFFFF;
        ULONG cw = g_CrumbIts ? READ_REGISTER_ULONG((PULONG)(g_CrumbIts + 0x88)) : 0xFFFFFFFF;
        if ((sec % 5) == 0) {                                // 1 line pair per 5 s keeps the 0xE0000-byte crumb from filling in a few hours
            CrumbLine("tick", sec, 0);
            CrumbLine("its cr/cw", cr, cw);
        }
        CrumbDiskFlush();
        sec++;
        KeDelayExecutionThread(KernelMode, FALSE, &d);
    }
    PsTerminateSystemThread(STATUS_SUCCESS);
}

static VOID CrumbStart(VOID)
{
    PHYSICAL_ADDRESS pa; OBJECT_ATTRIBUTES oa;
    pa.QuadPart = (LONGLONG)CRUMB_PA;
    g_WdtDiag[4] = 10;                                       // stage: CrumbStart entered
    g_Crumb = (PUCHAR)MmMapIoSpace(pa, 0x100000, MmNonCached);
    if (!g_Crumb) { g_WdtDiag[4] = 11; return; }            // stage 11: crumb RAM map failed -> no thread at all
    KeInitializeSpinLock(&g_CrumbLock);
    // keep the previous boot's text (if the DRAM survived the reset) so that user mode can save it
    if (((PULONG)g_Crumb)[0] == CRUMB_SIG && ((PULONG)g_Crumb)[2] > 0 && ((PULONG)g_Crumb)[2] <= CRUMB_MAX) {
        ULONG n = ((PULONG)g_Crumb)[2];
        g_PrevCrumb = (PUCHAR)ExAllocatePoolWithTag(NonPagedPool, n, 'pcgD');
        if (g_PrevCrumb) { RtlCopyMemory(g_PrevCrumb, g_Crumb + 12, n); g_PrevLen = n; }
    }
    ((PULONG)g_Crumb)[0] = CRUMB_SIG;
    ((PULONG)g_Crumb)[1] = 0;
    ((PULONG)g_Crumb)[2] = 0;
    g_CrumbPos = 0;
    CrumbPut("dbgcap start\n", 13);
    KeInitializeCallbackRecord(&g_BcRec);
    g_BcReg = KeRegisterBugCheckCallback(&g_BcRec, BugCheckCb, g_BcBuf, sizeof(g_BcBuf), (PUCHAR)"dbgcap");
    CrumbPut(g_BcReg ? "bugcheck cb on\n" : "bugcheck cb FAILED\n", g_BcReg ? 15 : 19);
    PsSetLoadImageNotifyRoutine(CrumbImageNotify);
    pa.QuadPart = 0x17140000;
    g_CrumbIts = (PUCHAR)MmMapIoSpace(pa, 0x1000, MmNonCached);
    g_CrumbOn = 1;
    g_WdtDiag[4] = 12;                                       // stage: about to create the thread
    InitializeObjectAttributes(&oa, NULL, OBJ_KERNEL_HANDLE, NULL, NULL);
    g_WdtDiag[5] = (ULONG)PsCreateSystemThread(&g_CrumbThread, THREAD_ALL_ACCESS, &oa, NULL, NULL, CrumbThread, NULL);   // until the thread runs: its NTSTATUS (0 = created)
    if (g_WdtDiag[5] != 0) g_WdtDiag[4] = 14;                // 14 = creation failed (status in [5]); 12 stays if the thread has not run yet, otherwise the thread already moved it on
    if (g_WdtDiag[5] == 0) {
        ObReferenceObjectByHandle(g_CrumbThread, THREAD_ALL_ACCESS, NULL, KernelMode, (PVOID *)&g_CrumbThreadObj, NULL);
        ZwClose(g_CrumbThread);
    }
}

static VOID CrumbStop(VOID)
{
    if (!g_CrumbOn) return;
    g_CrumbOn = 0;
    PsRemoveLoadImageNotifyRoutine(CrumbImageNotify);
    if (g_BcReg) { KeDeregisterBugCheckCallback(&g_BcRec); g_BcReg = FALSE; }
    if (g_CrumbThreadObj) { KeWaitForSingleObject(g_CrumbThreadObj, Executive, KernelMode, FALSE, NULL); ObDereferenceObject(g_CrumbThreadObj); g_CrumbThreadObj = NULL; }
    if (g_WdtGuard) { BeatStop(); GhSmc(GH_WDT_CONTROL, 2u, 0, 0); g_WdtGuard = FALSE; }     // clean unload: pings stop, so turn the watchdog off again
    CrumbPut("dbgcap stop\n", 12);
    CrumbDiskFlush();
    if (g_CrumbFile) { ZwClose(g_CrumbFile); g_CrumbFile = NULL; }
    if (g_PrevCrumb) { ExFreePoolWithTag(g_PrevCrumb, 'pcgD'); g_PrevCrumb = NULL; g_PrevLen = 0; }
}

// ---- ITS stall fixer (runs from DriverEntry on) -------------------------------------------------------------------------------------------------------------------------------------------
// Gunyah's virtual ITS stalls the command queue (GITS_CREADR bit 0) on Windows' first MAPD commands (event-id size 9 is larger than the 8 bits it supports, and the level-2 device-table page is missing).
// A stalled queue hangs Windows' boot, so this does what rpfix.ps1 did: clamp the MAPD size to 7, install a zeroed level-2 page into the device table when its L1 entry is empty, then GITS_CWRITER.Retry.
// Any other stalled command is replaced by a SYNC so the queue always moves on.
static volatile LONG g_FixOn;
static PUCHAR g_FixIts;
static ULONG g_FixLastCr = 0xFFFFFFFFu;     // not a valid CREADR: a MAPD stalled in slot 0 (cr == 1) must not be taken for "already tried"
static ULONG g_FixCount;
static ULONG g_FixPool;
static const ULONGLONG g_PoolPa[4] = { 0xD7FF4000ull, 0xD7FF5000ull, 0xD7FF6000ull, 0xD7FF7000ull };

static VOID FixLog(const char *t, ULONG a, ULONG b)
{
    CrumbLine(t, a, b);
    UCHAR h[18]; int q;
    PutBytes((const UCHAR *)t, (ULONG)strlen(t));
    for (q = 0; q < 8; q++) h[q] = (UCHAR)Hex[(a >> (28 - 4 * q)) & 15];
    h[8] = ' ';
    for (q = 0; q < 8; q++) h[9 + q] = (UCHAR)Hex[(b >> (28 - 4 * q)) & 15];
    h[17] = (UCHAR)10;
    PutBytes(h, 18);
}

static VOID FixCheck(VOID)
{
    ULONG cr, cw, off, op, i;
    ULONGLONG qpa;
    PHYSICAL_ADDRESS pa;
    PULONG c;
    if (!g_FixOn || !g_FixIts) return;
    cr = READ_REGISTER_ULONG((PULONG)(g_FixIts + 0x90));
    if (!(cr & 1)) { g_FixLastCr = 0xFFFFFFFFu; return; }
    qpa = ((ULONGLONG)READ_REGISTER_ULONG((PULONG)(g_FixIts + 0x84)) << 32 | READ_REGISTER_ULONG((PULONG)(g_FixIts + 0x80))) & 0x000FFFFFFFFFF000ull;
    if (!qpa) return;
    pa.QuadPart = (LONGLONG)qpa;
    c = (PULONG)MmMapIoSpace(pa, 0x1000, MmNonCached);
    if (!c) return;
    off = cr & 0xFE0;
    c = (PULONG)((PUCHAR)c + off);
    op = c[0] & 0xFF;
    FixLog("dbgcap: ITS stall cr/op ", cr, op);
    FixLog("dbgcap: cmd w0/w1 ", c[0], c[1]);
    FixLog("dbgcap: cmd w2/w3 ", c[2], c[3]);
    FixLog("dbgcap: cmd w4/w5 ", c[4], c[5]);
    if (op == 8 && cr != g_FixLastCr) {
        ULONG dev = c[1], size = c[2] & 0x1F;
        ULONGLONG l1pa = ((ULONGLONG)READ_REGISTER_ULONG((PULONG)(g_FixIts + 0x104)) << 32 | READ_REGISTER_ULONG((PULONG)(g_FixIts + 0x100))) & 0x0000FFFFFFFFF000ull;
        ULONGLONG ent = l1pa + 8ull * (dev >> 9);
        PUCHAR l1;
        if (size > 7) c[2] = (c[2] & ~0x1Fu) | 7;
        pa.QuadPart = (LONGLONG)(ent & ~0xFFFull);
        l1 = (PUCHAR)MmMapIoSpace(pa, 0x1000, MmNonCached);
        if (l1) {
            PULONG e = (PULONG)(l1 + (ent & 0xFFF));
            if (e[0] == 0 && e[1] == 0 && g_FixPool < 4) {
                PHYSICAL_ADDRESS pp; PULONG pg;
                pp.QuadPart = (LONGLONG)g_PoolPa[g_FixPool];
                pg = (PULONG)MmMapIoSpace(pp, 0x1000, MmNonCached);
                if (pg) {
                    for (i = 0; i < 1024; i++) pg[i] = 0;
                    e[0] = (ULONG)g_PoolPa[g_FixPool];
                    e[1] = 0x80000000u | (ULONG)(g_PoolPa[g_FixPool] >> 32);
                    MmUnmapIoSpace(pg, 0x1000);
                    FixLog("dbgcap: L2 page installed dev/pa ", dev, (ULONG)g_PoolPa[g_FixPool]);
                    g_FixPool++;
                }
            }
            MmUnmapIoSpace(l1, 0x1000);
        }
        FixLog("dbgcap: MAPD size fixed dev/size ", dev, size);
    } else {
        for (i = 0; i < 8; i++) c[i] = 0;
        c[0] = 5;                                  // SYNC
        FixLog("dbgcap: stalled command replaced by SYNC ", cr, op);
    }
    g_FixLastCr = cr;
    g_FixCount++;
    KeMemoryBarrier();
    MmUnmapIoSpace((PUCHAR)c - off, 0x1000);
    cw = READ_REGISTER_ULONG((PULONG)(g_FixIts + 0x88));
    WRITE_REGISTER_ULONG((PULONG)(g_FixIts + 0x88), cw | 1);        // GITS_CWRITER.Retry
}

// The HAL waits for the ITS command queue with one CPU stuck (interrupts masked), and a timer DPC queued on that CPU never runs: the fixer is a thread pinned to CPU 1 instead.
#define FIX_THREADS 2
static PETHREAD g_FixThreadObj[FIX_THREADS];
static KSPIN_LOCK g_FixLock;

static VOID FixThread(PVOID Ctx)
{
    LARGE_INTEGER d; KIRQL old;
    ULONG n = (ULONG)(ULONG_PTR)Ctx;
    KeSetSystemAffinityThreadEx((KAFFINITY)1 << (1 + n));   // CPU 1 and CPU 2 (the stuck CPU is usually CPU 0); ignored if there is no such CPU
    d.QuadPart = -10000LL;                                  // 1 ms
    while (g_FixOn) {
        KeAcquireSpinLock(&g_FixLock, &old);
        FixCheck();
        KeReleaseSpinLock(&g_FixLock, old);
        KeDelayExecutionThread(KernelMode, FALSE, &d);
    }
    PsTerminateSystemThread(STATUS_SUCCESS);
}

static VOID FixStart(VOID)
{
    PHYSICAL_ADDRESS pa; OBJECT_ATTRIBUTES oa; ULONG n;
    pa.QuadPart = 0x17140000;
    g_FixIts = (PUCHAR)MmMapIoSpace(pa, 0x1000, MmNonCached);
    if (!g_FixIts) return;
    KeInitializeSpinLock(&g_FixLock);
    ExSetTimerResolution(10000, TRUE);
    g_FixOn = 1;
    for (n = 0; n < FIX_THREADS; n++) {
        HANDLE h;
        InitializeObjectAttributes(&oa, NULL, OBJ_KERNEL_HANDLE, NULL, NULL);
        if (NT_SUCCESS(PsCreateSystemThread(&h, THREAD_ALL_ACCESS, &oa, NULL, NULL, FixThread, (PVOID)(ULONG_PTR)n))) {
            ObReferenceObjectByHandle(h, THREAD_ALL_ACCESS, NULL, KernelMode, (PVOID *)&g_FixThreadObj[n], NULL);
            ZwClose(h);
        }
    }
}

static VOID FixStop(VOID)
{
    ULONG n;
    if (!g_FixOn) return;
    g_FixOn = 0;
    for (n = 0; n < FIX_THREADS; n++) if (g_FixThreadObj[n]) { KeWaitForSingleObject(g_FixThreadObj[n], Executive, KernelMode, FALSE, NULL); ObDereferenceObject(g_FixThreadObj[n]); g_FixThreadObj[n] = NULL; }
    ExSetTimerResolution(0, FALSE);
    if (g_FixIts) MmUnmapIoSpace(g_FixIts, 0x1000);
}

// IOCTL_DBGCAP_POLL  in: { ULONGLONG Base; ULONG PeriodMs }  (PeriodMs 0 = stop)   out: { ULONG Runs; ULONG WithCtx; ULONGLONG Ctx }
// The interrupts of the WCN7850 never reach the qcwlan driver (Gunyah vGIC), so its MHI event-ring handlers are called from here instead: a periodic timer DPC runs
// ring 0 (MHICtrlEventTask, base+0x234640) and rings 1.. (MHIEventTask, base+0x2346c0) with the MHI controller pointer that the patched driver publishes at base+0x42B800.
#define POLL_CTX_RVA 0x42B800ull
#define POLL_FN0_RVA 0x234640ull
#define POLL_FN1_RVA 0x2346C0ull
typedef VOID (*PFN_MHI_TASK)(PVOID Ctx);
// bottom half of the PCIe interrupt (function at base+0x1B63F8: x0 = HIF softc, x1 = MSI vector, x3 = pointer to a flag word): for vectors >= 2 it runs the copy-engine / ext-group service
#define POLL_HIF_RVA 0x42B808ull
#define POLL_BH_RVA 0x1B63F8ull
typedef VOID (*PFN_HIF_BH)(PVOID Hif, ULONG Vec, ULONGLONG A2, PVOID A3);
static ULONG g_PollZero[8];
static volatile LONG g_PollBh;
// DpPoll (Services\dbgcap\DpPoll = 1, guard.cmd ... dppoll): also run the data-path ext groups, which the MSI vectors above 10 would normally trigger.  hif_register_ext_group (image+0x1FC198) keeps a
// pointer to each group at hif+0x480+8*i (count at hif+0x4A8); group+0xA8 = callback context, group+0xB0 = callback (dp_service_srngs-like: ctx, budget, cpu).  Without this the REO destination
// rings (received data frames, incl. the EAPOL of the 4-way handshake) and the TX completion rings are never serviced.  2026-10-28: <LAB_SSID> associates but the handshake frame never arrives.
static BOOLEAN g_DpPoll;
static BOOLEAN g_PollPassive;          // Services\dbgcap\PollPassive = 1: bottom halves at PASSIVE_LEVEL with separate exclusion for CE and ext groups (see PollWork)
static volatile LONG g_PollDp;
static volatile LONG g_PollDpBusy;
static ULONGLONG g_PollBase;
static KSPIN_LOCK g_PollLock;
// flag take/release under the spin lock (the Interlocked intrinsics do not link in this build); the lock is held for the flag only, never across the callbacks
static BOOLEAN PollTake(volatile LONG *f)
{
    KIRQL ol; BOOLEAN t;
    KeAcquireSpinLock(&g_PollLock, &ol);
    t = (*f == 0); if (t) *f = 1;
    KeReleaseSpinLock(&g_PollLock, ol);
    return t;
}
static VOID PollRelease(volatile LONG *f)
{
    KIRQL ol;
    KeAcquireSpinLock(&g_PollLock, &ol);
    *f = 0;
    KeReleaseSpinLock(&g_PollLock, ol);
}
static VOID PollDpGroups(PUCHAR hif)
{
    ULONG ng, gi;
    if (!MmIsAddressValid(hif + 0x4A8)) return;
    ng = *(PULONG)(hif + 0x4A8);
    if (ng > 8) ng = 8;
    for (gi = 0; gi < ng; gi++) {
        PUCHAR grp = NULL; PVOID gctx; PVOID gfn;
        if (!MmIsAddressValid(hif + 0x480 + 8 * gi)) break;
        grp = *(PUCHAR *)(hif + 0x480 + 8 * gi);
        if (!grp || !MmIsAddressValid(grp) || !MmIsAddressValid(grp + 0xB8)) continue;
        gctx = *(PVOID *)(grp + 0xA8); gfn = *(PVOID *)(grp + 0xB0);
        // the callback must lie inside the driver image
        if (!gctx || (ULONGLONG)gfn < g_PollBase || (ULONGLONG)gfn >= g_PollBase + 0x2EC000ull) continue;
        ((int (*)(PVOID, ULONG, ULONG))gfn)(gctx, 64, 0);
        g_PollDp++;
    }
}
static KTIMER g_PollTimer;
static KDPC g_PollDpc;
static volatile LONG g_PollOn;
static volatile LONG g_PollBusy;
static KSPIN_LOCK g_PollLock;
static volatile LONG g_PollRuns;
static volatile LONG g_PollWithCtx;
static volatile ULONGLONG g_PollCtx;

// The MHI callbacks (AMSS entry -> open IPC channels) wait for a worker thread with KeWaitForSingleObject, so the ring handlers must run at PASSIVE_LEVEL, and a handler that
// is blocked must not stop the next tick from processing the command-completion event it is waiting for: the timer DPC queues the work to up to POLL_SLOTS system work items.
#define POLL_SLOTS 3
typedef struct { WORK_QUEUE_ITEM Wi; volatile LONG Busy; } POLL_WI;
static POLL_WI g_PollWi[POLL_SLOTS];

static VOID PollWork(PVOID Param)
{
    POLL_WI *w = (POLL_WI *)Param;
    PVOID *slot; PVOID mhi;
    g_PollRuns++;
    slot = (PVOID *)(g_PollBase + POLL_CTX_RVA);
    if (g_PollOn && MmIsAddressValid(slot)) {
        mhi = *slot;
        if (mhi && MmIsAddressValid(mhi) && MmIsAddressValid((PUCHAR)mhi + 0x7e30)) {
            g_PollCtx = (ULONGLONG)mhi;
            g_PollWithCtx++;
            ((PFN_MHI_TASK)(g_PollBase + POLL_FN0_RVA))(mhi);
            ((PFN_MHI_TASK)(g_PollBase + POLL_FN1_RVA))(mhi);
        }
        slot = (PVOID *)(g_PollBase + POLL_HIF_RVA);
        if (MmIsAddressValid(slot) && *slot) {
            PUCHAR hif = (PUCHAR)*slot;
            PUCHAR p9e0 = NULL, pmask = NULL, pbase = NULL;
            if (MmIsAddressValid(hif + 0x9e0) && MmIsAddressValid(hif + 0xb68)) { p9e0 = *(PUCHAR *)(hif + 0x9e0); pmask = *(PUCHAR *)(hif + 0xb68); }
            if (p9e0 && MmIsAddressValid(p9e0) && MmIsAddressValid(p9e0 + 0xc8)) pbase = *(PUCHAR *)(p9e0 + 0xc8);
            if (pmask && pbase && MmIsAddressValid(pmask) && MmIsAddressValid(pbase + 0x38d18) && MmIsAddressValid(hif + 0xb70) && MmIsAddressValid(hif + 0xa40)) {
                KIRQL old; ULONG vec; BOOLEAN take;
                if (g_PollPassive) {
                    // PollPassive (guard.cmd ... passive): the driver's own interrupt thread runs this bottom half and the ext-group callbacks at PASSIVE_LEVEL (they may wait: e.g. the vdev-stopped
                    // event of a disconnect), so no IRQL raise here; CE bottom half and ext groups exclude only themselves, so one blocked in a wait cannot keep the other from delivering its completion.
                    if (PollTake(&g_PollBusy)) {
                        for (vec = 2; vec < 16; vec++) ((PFN_HIF_BH)(g_PollBase + POLL_BH_RVA))(hif, vec, 0, g_PollZero);
                        g_PollBh++;
                        PollRelease(&g_PollBusy);
                    }
                    if (g_DpPoll && PollTake(&g_PollDpBusy)) {
                        PollDpGroups(hif);
                        PollRelease(&g_PollDpBusy);
                    }
                    w->Busy = 0;
                    return;
                }
                KeRaiseIrql(DISPATCH_LEVEL, &old);
                // a real interrupt never runs this bottom half on two CPUs at once: let only one work item in at a time (the others skip this tick)
                KeAcquireSpinLockAtDpcLevel(&g_PollLock);
                take = (g_PollBusy == 0); if (take) g_PollBusy = 1;
                KeReleaseSpinLockFromDpcLevel(&g_PollLock);
                if (take) {
                    for (vec = 2; vec < 16; vec++) ((PFN_HIF_BH)(g_PollBase + POLL_BH_RVA))(hif, vec, 0, g_PollZero);
                    g_PollBh++;
                    if (g_DpPoll) PollDpGroups(hif);
                    KeAcquireSpinLockAtDpcLevel(&g_PollLock);
                    g_PollBusy = 0;
                    KeReleaseSpinLockFromDpcLevel(&g_PollLock);
                }
                KeLowerIrql(old);
            }
        }
    }
    w->Busy = 0;
}

static VOID PollDpc(PKDPC Dpc, PVOID Ctx, PVOID A1, PVOID A2)
{
    ULONG i;
    UNREFERENCED_PARAMETER(Dpc); UNREFERENCED_PARAMETER(Ctx); UNREFERENCED_PARAMETER(A1); UNREFERENCED_PARAMETER(A2);
    if (!g_PollOn) return;
    for (i = 0; i < POLL_SLOTS; i++) {
        if (!g_PollWi[i].Busy) {
            g_PollWi[i].Busy = 1;
            ExInitializeWorkItem(&g_PollWi[i].Wi, PollWork, &g_PollWi[i]);
            ExQueueWorkItem(&g_PollWi[i].Wi, DelayedWorkQueue);
            break;
        }
    }
}

static VOID PollWaitIdle(VOID)
{
    ULONG i, n;
    for (n = 0; n < 2000; n++) {
        LARGE_INTEGER d;
        for (i = 0; i < POLL_SLOTS; i++) if (g_PollWi[i].Busy) break;
        if (i == POLL_SLOTS) return;
        d.QuadPart = -10000LL * 5;
        KeDelayExecutionThread(KernelMode, FALSE, &d);
    }
}

static NTSTATUS PollCtl(PULONG in, PULONG out)
{
    ULONGLONG base = ((ULONGLONG)in[1] << 32) | in[0];
    ULONG ms = in[2];
    if (ms == 0xFFFFFFFEu) {
        // "stop the data-path (ext group) polling only": hif_deregister_exec_group frees the groups while the driver is disabled; a poll that still calls their callbacks would run into freed memory.  MHI/CE polling goes on
        // (the MHI power-down needs the ring handlers).  Waits until a call that is already inside the callbacks has returned.
        ULONG n;
        g_DpPoll = FALSE;
        for (n = 0; n < 2000 && g_PollDpBusy; n++) { LARGE_INTEGER d; d.QuadPart = -10000LL * 5; KeDelayExecutionThread(KernelMode, FALSE, &d); }
        out[0] = (ULONG)g_PollRuns; out[1] = (ULONG)g_PollWithCtx; out[2] = (ULONG)g_PollCtx; out[3] = (ULONG)g_PollBh;
        return STATUS_SUCCESS;
    }
    if (ms == 0) {
        if (g_PollOn) { g_PollOn = 0; KeCancelTimer(&g_PollTimer); KeFlushQueuedDpcs(); PollWaitIdle(); ExSetTimerResolution(0, FALSE); }
    } else if (!g_PollOn) {
        LARGE_INTEGER due;
        { ULONG q; for (q = 0; q < POLL_SLOTS; q++) g_PollWi[q].Busy = 0; }
        g_PollBase = base; g_PollRuns = 0; g_PollWithCtx = 0; g_PollCtx = 0; g_PollBusy = 0; g_PollDpBusy = 0;
        KeInitializeSpinLock(&g_PollLock);
        KeInitializeSpinLock(&g_PollLock);
        KeInitializeTimerEx(&g_PollTimer, SynchronizationTimer);
        KeInitializeDpc(&g_PollDpc, PollDpc, NULL);
        ExSetTimerResolution(10000, TRUE);                                  // 1 ms timer tick
        g_PollOn = 1;
        due.QuadPart = -10000LL * (LONGLONG)ms;
        KeSetTimerEx(&g_PollTimer, due, (LONG)ms, &g_PollDpc);
    }
    out[0] = (ULONG)g_PollRuns; out[1] = (ULONG)g_PollWithCtx; out[2] = (ULONG)g_PollCtx; out[3] = (ULONG)g_PollBh;
    return STATUS_SUCCESS;
}

// ---- SPI interrupts for the WCN7850 (2026-10-30) ----------------------------------------------------------------------------------------------------------------------------------------------
// The LPI path never reaches this VM's Windows, but the chip's MSIs can be sent to the GIC MBI frame (qcom,pci-msi, 0x17110040) with data = INTID 800 + vector: they arrive as SPIs 800.. (SPI window test, NEXT.md 0az).
// IOCTL_DBGCAP_IRQ  in: { ULONG Mode; ULONG FirstGsiv; ULONG Count; ULONG Flags }   out: 70 ULONGs: Cnt[16], Status[16], Kicks, KickFlag, MatrixStatus[32], PdoCount, ChosenIrql, Combo
//   Mode 0 = disconnect all, 1 = connect Count SPIs from FirstGsiv (Flags bit 0: every interrupt also queues the poll DPC = interrupt-driven polling), 2 = just report, 3 = set the kick flag from Flags.
#define IOCTL_DBGCAP_IRQ CTL_CODE(DEV_TYPE, 0xA09, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IRQ_MAX 16
static PKINTERRUPT g_IrqObj[IRQ_MAX];
static volatile LONG g_IrqCnt[IRQ_MAX];
static LONG g_IrqSt[IRQ_MAX];
static volatile LONG g_IrqKick;
static volatile LONG g_IrqKicks;

// Kick thread (NEXT.md 0be): rm9irq.sys (the ACPI device RM9I0001 that owns the SPIs) signals the named synchronization event \BaseNamedObjects\Rm9IrqKick from its DPC whenever one of the chip's
// MSIs arrives; this thread waits for it and queues the poll DPC, so the MHI/CE/DP bottom halves run on the interrupt instead of on the timer.  Mode 4 of IOCTL_DBGCAP_IRQ starts/stops it.
static PKEVENT g_KickEvt;
static HANDLE g_KickEvtH;
static HANDLE g_KickThrH;
static PKTHREAD g_KickThr;
static volatile LONG g_KickStop;
static volatile LONG g_KickWakes;
static volatile LONG g_KickTimeouts;
static volatile LONG g_KickBurstMs;          // after an interrupt keep polling every this many ms (0 = off) ...
static volatile LONG g_KickTailMs;           // ... until this long has passed without another interrupt (NAPI-like: fast polling only under load, nothing when idle)
static volatile LONG g_KickBursts;

static VOID KickThread(PVOID Ctx)
{
    LARGE_INTEGER to, zero, dly;
    UNREFERENCED_PARAMETER(Ctx);
    to.QuadPart = -10000LL * 500;                       // wake up twice a second to see the stop flag
    zero.QuadPart = 0;
    while (!g_KickStop) {
        NTSTATUS st = KeWaitForSingleObject(g_KickEvt, Executive, KernelMode, FALSE, &to);
        if (g_KickStop) break;
        if (st == STATUS_SUCCESS) {
            g_KickWakes++;
            if (g_PollOn && KeInsertQueueDpc(&g_PollDpc, NULL, NULL)) g_IrqKicks++;
            if (g_KickBurstMs > 0 && g_KickTailMs > 0) {
                ULONGLONG last = KeQueryInterruptTime();
                dly.QuadPart = -10000LL * g_KickBurstMs;
                while (!g_KickStop && (KeQueryInterruptTime() - last) < 10000ULL * (ULONGLONG)g_KickTailMs) {
                    KeDelayExecutionThread(KernelMode, FALSE, &dly);
                    g_KickBursts++;
                    if (g_PollOn) KeInsertQueueDpc(&g_PollDpc, NULL, NULL);
                    if (KeWaitForSingleObject(g_KickEvt, Executive, KernelMode, FALSE, &zero) == STATUS_SUCCESS) { g_KickWakes++; last = KeQueryInterruptTime(); }
                }
            }
        } else {
            g_KickTimeouts++;
        }
    }
    PsTerminateSystemThread(STATUS_SUCCESS);
}

static NTSTATUS KickStart(VOID)
{
    UNICODE_STRING nm = RTL_CONSTANT_STRING(L"\\BaseNamedObjects\\Rm9IrqKick");
    OBJECT_ATTRIBUTES oa;
    NTSTATUS st;
    if (g_KickThr) return STATUS_SUCCESS;
    g_KickEvt = IoCreateSynchronizationEvent(&nm, &g_KickEvtH);       // opens the event rm9irq.sys created (or creates it first)
    DbgPrint("dbgcap: kick event %p\n", g_KickEvt);
    if (!g_KickEvt) return STATUS_INSUFFICIENT_RESOURCES;
    g_KickStop = 0; g_KickWakes = 0; g_KickTimeouts = 0;
    InitializeObjectAttributes(&oa, NULL, OBJ_KERNEL_HANDLE, NULL, NULL);
    st = PsCreateSystemThread(&g_KickThrH, THREAD_ALL_ACCESS, &oa, NULL, NULL, KickThread, NULL);
    if (!NT_SUCCESS(st)) { ZwClose(g_KickEvtH); g_KickEvtH = NULL; g_KickEvt = NULL; return st; }
    st = ObReferenceObjectByHandle(g_KickThrH, THREAD_ALL_ACCESS, *PsThreadType, KernelMode, (PVOID *)&g_KickThr, NULL);
    if (!NT_SUCCESS(st)) { g_KickStop = 1; KeSetEvent(g_KickEvt, IO_NO_INCREMENT, FALSE); }
    return st;
}

static VOID KickStop(VOID)
{
    if (!g_KickThr && !g_KickThrH) return;
    g_KickStop = 1;
    if (g_KickEvt) KeSetEvent(g_KickEvt, IO_NO_INCREMENT, FALSE);
    if (g_KickThr) { KeWaitForSingleObject(g_KickThr, Executive, KernelMode, FALSE, NULL); ObDereferenceObject(g_KickThr); g_KickThr = NULL; }
    if (g_KickThrH) { ZwClose(g_KickThrH); g_KickThrH = NULL; }
    if (g_KickEvtH) { ZwClose(g_KickEvtH); g_KickEvtH = NULL; }
    g_KickEvt = NULL;
}

static BOOLEAN IrqIsr(PKINTERRUPT Intr, PVOID Ctx)
{
    ULONG idx = (ULONG)(ULONG_PTR)Ctx;
    UNREFERENCED_PARAMETER(Intr);
    if (idx < IRQ_MAX) g_IrqCnt[idx]++;                                    // plain increments: a diagnostic counter, a lost update on another CPU does not matter
    if (g_IrqKick && g_PollOn) { if (KeInsertQueueDpc(&g_PollDpc, NULL, NULL)) g_IrqKicks++; }
    return TRUE;
}

static VOID IrqDisconnectAll(VOID)
{
    ULONG i;
    for (i = 0; i < IRQ_MAX; i++) {
        if (g_IrqObj[i]) {
            IO_DISCONNECT_INTERRUPT_PARAMETERS d;
            RtlZeroMemory(&d, sizeof(d));
            d.Version = CONNECT_FULLY_SPECIFIED;
            d.ConnectionContext.InterruptObject = g_IrqObj[i];
            IoDisconnectInterruptEx(&d);
            g_IrqObj[i] = NULL;
        }
    }
}

// IoConnectInterruptEx wants the PDO of the device the interrupt belongs to (_In_, not optional) and a translated (Vector, Irql).  We have neither, so the first connect tries a small matrix: PDO in { PCI PDOs found by
// name, none } x Irql 3..12 with Vector = GSIV, and remembers the first pair that the HAL accepts.  Matrix statuses are returned (out[34..65]) so a failure still tells what was rejected.
NTKERNELAPI PDEVICE_OBJECT IoGetDeviceAttachmentBaseRef(_In_ PDEVICE_OBJECT DeviceObject);      // exported by ntoskrnl, not declared by the headers used here (an implicit int would cut the pointer)
static PDEVICE_OBJECT g_IrqPdo[2];
static ULONG g_IrqPdoN;
static LONG g_IrqCombo = -1;             // index into the matrix once one worked
static ULONG g_IrqChosenIrql;
static LONG g_IrqMx[32];

static VOID IrqFindPdos(VOID)
{
    ULONG n;
    if (g_IrqPdoN) return;
    for (n = 0; n < 0x60 && g_IrqPdoN < 2; n++) {
        WCHAR nm[40];
        UNICODE_STRING us; PFILE_OBJECT fo = NULL; PDEVICE_OBJECT top = NULL; NTSTATUS st;
        static const WCHAR hexd[] = L"0123456789ABCDEF";
        RtlCopyMemory(nm, L"\\Device\\NTPNP_PCI00", 19 * sizeof(WCHAR));
        nm[19] = hexd[(n >> 4) & 0xF]; nm[20] = hexd[n & 0xF]; nm[21] = 0;
        RtlInitUnicodeString(&us, nm);
        st = IoGetDeviceObjectPointer(&us, FILE_READ_DATA, &fo, &top);
        if (NT_SUCCESS(st)) {
            PDEVICE_OBJECT base = IoGetDeviceAttachmentBaseRef(top);
            ObDereferenceObject(fo);
            if (base) g_IrqPdo[g_IrqPdoN++] = base;
        }
    }
}

static NTSTATUS IrqConnectOne(ULONG idx, ULONG gsiv, PDEVICE_OBJECT pdo, KIRQL irql)
{
    IO_CONNECT_INTERRUPT_PARAMETERS p;
    NTSTATUS st;
    RtlZeroMemory(&p, sizeof(p));
    p.Version = CONNECT_FULLY_SPECIFIED;
    p.FullySpecified.PhysicalDeviceObject = pdo;
    p.FullySpecified.InterruptObject = &g_IrqObj[idx];
    p.FullySpecified.ServiceRoutine = IrqIsr;
    p.FullySpecified.ServiceContext = (PVOID)(ULONG_PTR)idx;
    p.FullySpecified.SpinLock = NULL;
    p.FullySpecified.SynchronizeIrql = irql;
    p.FullySpecified.FloatingSave = FALSE;
    p.FullySpecified.ShareVector = FALSE;
    p.FullySpecified.Vector = gsiv;            // ARM64 has no HalGetInterruptVector: the system vector of an SPI is its GSIV
    p.FullySpecified.Irql = irql;
    p.FullySpecified.InterruptMode = Latched;
    p.FullySpecified.ProcessorEnableMask = 0xFF;
    p.FullySpecified.Group = 0;
    st = IoConnectInterruptEx(&p);
    if (!NT_SUCCESS(st)) g_IrqObj[idx] = NULL;
    return st;
}

static NTSTATUS IrqCtl(PULONG in, PULONG out)
{
    ULONG mode = in[0], first = in[1], count = in[2], flags = in[3], i;
    if (mode == 0) { g_IrqKick = 0; IrqDisconnectAll(); }
    else if (mode == 1) {
        PDEVICE_OBJECT usePdo = NULL; KIRQL useIrql = 5;
        if (count > IRQ_MAX) count = IRQ_MAX;
        g_IrqKick = (flags & 1) ? 1 : 0;
        IrqFindPdos();
        if (g_IrqCombo < 0 && count > 0 && !g_IrqObj[0]) {
            ULONG pi, ir, k = 0;
            for (pi = 0; pi < g_IrqPdoN + 1 && g_IrqCombo < 0; pi++) {
                PDEVICE_OBJECT pdo = (pi < g_IrqPdoN) ? g_IrqPdo[pi] : NULL;
                for (ir = 3; ir <= 12 && k < 32; ir++, k++) {
                    NTSTATUS st = IrqConnectOne(0, first, pdo, (KIRQL)ir);
                    g_IrqMx[k] = (LONG)st;
                    if (NT_SUCCESS(st)) { g_IrqCombo = (LONG)(pi * 16 + ir); g_IrqChosenIrql = ir; usePdo = pdo; useIrql = (KIRQL)ir; g_IrqSt[0] = 0; break; }
                }
            }
        } else if (g_IrqCombo >= 0) {
            ULONG pi = (ULONG)g_IrqCombo >> 4;
            usePdo = (pi < g_IrqPdoN) ? g_IrqPdo[pi] : NULL; useIrql = (KIRQL)g_IrqChosenIrql;
        }
        if (g_IrqCombo >= 0) {
            for (i = 0; i < count; i++) {
                if (g_IrqObj[i]) { g_IrqSt[i] = 0; continue; }
                g_IrqSt[i] = (LONG)IrqConnectOne(i, first + i, usePdo, useIrql);
            }
        } else {
            for (i = 0; i < count; i++) g_IrqSt[i] = g_IrqMx[0];
        }
    }
    else if (mode == 3) { g_IrqKick = (flags & 1) ? 1 : 0; }
    else if (mode == 4) {                                                   // kick thread on rm9irq's event: Flags bit 0 = start, 0 = stop
        if (flags & 1) {
            NTSTATUS ks;
            g_KickBurstMs = (LONG)((flags >> 8) & 0xFF);            // Flags bits 8..15 = follow-up poll period in ms, bits 16..31 = how long (ms) after the last interrupt; 0 = plain kick
            g_KickTailMs = (LONG)((flags >> 16) & 0xFFFF);
            ks = KickStart(); g_IrqSt[15] = (LONG)ks;
        } else KickStop();
    }
    for (i = 0; i < IRQ_MAX; i++) { out[i] = (ULONG)g_IrqCnt[i]; out[16 + i] = (ULONG)g_IrqSt[i]; }
    out[69] = (ULONG)g_KickWakes;
    out[32] = (ULONG)g_IrqKicks;
    out[33] = (ULONG)g_IrqKick;
    for (i = 0; i < 32; i++) out[34 + i] = (ULONG)g_IrqMx[i];
    out[66] = (ULONG)g_KickBursts;               // (was the PDO count of the old matrix connect)
    out[67] = g_IrqChosenIrql;
    out[68] = (ULONG)g_IrqCombo;
    return STATUS_SUCCESS;
}

NTSTATUS DcCreateClose(PDEVICE_OBJECT Dev, PIRP Irp)
{
    UNREFERENCED_PARAMETER(Dev);
    Irp->IoStatus.Status = STATUS_SUCCESS; Irp->IoStatus.Information = 0;
    IoCompleteRequest(Irp, IO_NO_INCREMENT);
    return STATUS_SUCCESS;
}

NTSTATUS DcIoctl(PDEVICE_OBJECT Dev, PIRP Irp)
{
    PIO_STACK_LOCATION sp = IoGetCurrentIrpStackLocation(Irp);
    NTSTATUS st = STATUS_INVALID_DEVICE_REQUEST;
    ULONG info = 0;
    UNREFERENCED_PARAMETER(Dev);
    if (sp->Parameters.DeviceIoControl.IoControlCode == IOCTL_DBGCAP_READ) {
        ULONG outLen = sp->Parameters.DeviceIoControl.OutputBufferLength;
        ULONG head = (ULONG)g_Head, tail = (ULONG)g_Tail, n, i;
        PUCHAR out = (PUCHAR)Irp->AssociatedIrp.SystemBuffer;
        if (head - tail > RING_SIZE) tail = head - RING_SIZE;       // overrun: oldest lines are gone
        n = head - tail;
        if (n > outLen) n = outLen;
        for (i = 0; i < n; i++) out[i] = g_Ring[(tail + i) & (RING_SIZE - 1)];
        g_Tail = (LONG)(tail + n);
        info = (ULONG)n;
        st = STATUS_SUCCESS;
    }
    else if (sp->Parameters.DeviceIoControl.IoControlCode == IOCTL_DBGCAP_READVA) {
        // in: { UINT64 Va; UINT32 Len }  out: Len bytes (a page that is not valid is returned as 0xEE bytes)
        ULONG inLen = sp->Parameters.DeviceIoControl.InputBufferLength;
        ULONG outLen = sp->Parameters.DeviceIoControl.OutputBufferLength;
        PUCHAR buf = (PUCHAR)Irp->AssociatedIrp.SystemBuffer;
        if (inLen >= 12) {
            ULONGLONG va = *(ULONGLONG *)buf;
            ULONG len = *(ULONG *)(buf + 8), i;
            if (len > outLen) len = outLen;
            if (len > 0x10000) len = 0x10000;
            for (i = 0; i < len; ) {
                ULONGLONG a = va + i;
                ULONG chunk = 0x1000 - (ULONG)(a & 0xFFF);
                if (chunk > len - i) chunk = len - i;
                if (MmIsAddressValid((PVOID)a)) {
                    __try { RtlCopyMemory(buf + i, (PVOID)a, chunk); }
                    __except (EXCEPTION_EXECUTE_HANDLER) { RtlFillMemory(buf + i, chunk, 0xEE); }
                } else {
                    RtlFillMemory(buf + i, chunk, 0xEE);
                }
                i += chunk;
            }
            info = len;
            st = STATUS_SUCCESS;
        } else {
            st = STATUS_INVALID_PARAMETER;
        }
    }
    else if (sp->Parameters.DeviceIoControl.IoControlCode == IOCTL_DBGCAP_ITSSTORM) {
        if (sp->Parameters.DeviceIoControl.InputBufferLength >= 12 && sp->Parameters.DeviceIoControl.OutputBufferLength >= 16) {
            ULONG inb[3];
            RtlCopyMemory(inb, Irp->AssociatedIrp.SystemBuffer, 12);
            st = ItsStorm(inb, (PULONG)Irp->AssociatedIrp.SystemBuffer);
            if (NT_SUCCESS(st)) info = 16;
        } else st = STATUS_INVALID_PARAMETER;
    }
    else if (sp->Parameters.DeviceIoControl.IoControlCode == IOCTL_DBGCAP_HPPIR) {
        if (sp->Parameters.DeviceIoControl.InputBufferLength >= 20 && sp->Parameters.DeviceIoControl.OutputBufferLength >= 64) {
            ULONG inb[5];
            RtlCopyMemory(inb, Irp->AssociatedIrp.SystemBuffer, 20);
            st = HppirProbe(inb, (PULONG)Irp->AssociatedIrp.SystemBuffer);
            if (NT_SUCCESS(st)) info = 64;
        } else st = STATUS_INVALID_PARAMETER;
    }
    else if (sp->Parameters.DeviceIoControl.IoControlCode == IOCTL_DBGCAP_TIMING) {
        if (sp->Parameters.DeviceIoControl.OutputBufferLength >= 48) {
            st = TimingTest((PULONG)Irp->AssociatedIrp.SystemBuffer);
            if (NT_SUCCESS(st)) info = 48;
        } else st = STATUS_INVALID_PARAMETER;
    }
    else if (sp->Parameters.DeviceIoControl.IoControlCode == IOCTL_DBGCAP_LPITEST) {
        if (sp->Parameters.DeviceIoControl.InputBufferLength >= 16 && sp->Parameters.DeviceIoControl.OutputBufferLength >= 88) {
            ULONG inb[4];
            RtlCopyMemory(inb, Irp->AssociatedIrp.SystemBuffer, 16);
            st = LpiTest(inb, (PULONG)Irp->AssociatedIrp.SystemBuffer);
            if (NT_SUCCESS(st)) info = 88;
        } else st = STATUS_INVALID_PARAMETER;
    }
    else if (sp->Parameters.DeviceIoControl.IoControlCode == IOCTL_DBGCAP_PREV) {
        // in: ULONG offset  out: ULONG total length of the previous boot's breadcrumbs, then up to (outLen - 4) bytes starting at offset
        ULONG outLen = sp->Parameters.DeviceIoControl.OutputBufferLength, off = 0, n = 0;
        if (sp->Parameters.DeviceIoControl.InputBufferLength >= 4 && outLen >= 4) {
            PUCHAR sb = (PUCHAR)Irp->AssociatedIrp.SystemBuffer;
            RtlCopyMemory(&off, sb, 4);
            if (off < g_PrevLen) { n = g_PrevLen - off; if (n > outLen - 4) n = outLen - 4; }
            if (n) RtlCopyMemory(sb + 4, g_PrevCrumb + off, n);
            RtlCopyMemory(sb, &g_PrevLen, 4);
            info = 4 + n; st = STATUS_SUCCESS;
        } else st = STATUS_INVALID_PARAMETER;
    }
    else if (sp->Parameters.DeviceIoControl.IoControlCode == IOCTL_DBGCAP_WDTTEST) {
        // in: ULONG 1 = stop pinging the watchdog on purpose (the phone must reset within ~31 s), 0 = resume   out: ULONG guard-on flag, ULONG hottest 0.1 C (signed), then g_WdtDiag[0..3]
        if (sp->Parameters.DeviceIoControl.InputBufferLength >= 4 && sp->Parameters.DeviceIoControl.OutputBufferLength >= 32) {
            PULONG sb = (PULONG)Irp->AssociatedIrp.SystemBuffer;
            g_WdtTestStop = (LONG)sb[0];
            if (sp->Parameters.DeviceIoControl.InputBufferLength >= 8) g_TempLimit = (sb[1] != 0) ? (LONG)sb[1] : TEMP_LIMIT_DC;   // optional 2nd input word: temperature limit in 0.1 C (0 = default)
            sb[0] = g_WdtGuard ? 1u : 0u; sb[1] = (ULONG)g_MaxTempDc;
            sb[2] = g_WdtDiag[0]; sb[3] = g_WdtDiag[1]; sb[4] = g_WdtDiag[2]; sb[5] = g_WdtDiag[3]; sb[6] = g_WdtDiag[4]; sb[7] = g_WdtDiag[5];
            info = 32;
            if (sp->Parameters.DeviceIoControl.OutputBufferLength >= 32 + 192) {      // optional: raw TSENS status words, 3 blocks x 16 sensors
                ULONG b2, n2;
                for (b2 = 0; b2 < 3; b2++) for (n2 = 0; n2 < 16; n2++) sb[8 + b2 * 16 + n2] = (g_Ts[b2] && n2 < g_TsN[b2]) ? READ_REGISTER_ULONG((PULONG)(g_Ts[b2] + 0xA0 + 4 * n2)) : 0;
                info = 32 + 192;
            }
            st = STATUS_SUCCESS;
        } else st = STATUS_INVALID_PARAMETER;
    }
    else if (sp->Parameters.DeviceIoControl.IoControlCode == IOCTL_DBGCAP_IRQ) {
        if (sp->Parameters.DeviceIoControl.InputBufferLength >= 16 && sp->Parameters.DeviceIoControl.OutputBufferLength >= 70 * sizeof(ULONG)) {
            ULONG inb[4];
            RtlCopyMemory(inb, Irp->AssociatedIrp.SystemBuffer, 16);
            st = IrqCtl(inb, (PULONG)Irp->AssociatedIrp.SystemBuffer);
            if (NT_SUCCESS(st)) info = 70 * sizeof(ULONG);
        } else st = STATUS_INVALID_PARAMETER;
    }
    else if (sp->Parameters.DeviceIoControl.IoControlCode == IOCTL_DBGCAP_GOV) {
        // in: { ULONG Mode; ULONG Arg }  Mode 0 = report only, 1 = governor off (Arg 0) / on (Arg 1), 2 = battery stop limit in 0.01 C (0 = default)   out: 52 ULONGs: [0] on, [1] thermal budget (0.1 %), [2] hottest 0.1 C, [3] ticks, [4..7] state index, [8..11] MHz, [12..15] ceiling index,
        //   [16..19] domain load (0.1 %), [20..35] per-CPU load (0.1 %), [36..39] states per domain, [40] last query status, [41] errors, [42] CPU count, [43] ups, [44] period ms, [45] EPSS on, [46] guard on, [47] wanted, [48] battery 0.01 C (-32768 = none), [49] battery budget cap (0.1 %), [50] battery stop limit (0.01 C), [51] seconds at the limit
        if (sp->Parameters.DeviceIoControl.InputBufferLength >= 8 && sp->Parameters.DeviceIoControl.OutputBufferLength >= 52 * sizeof(ULONG)) {
            PULONG sb = (PULONG)Irp->AssociatedIrp.SystemBuffer;
            ULONG mode = sb[0], arg = sb[1], k, dd;
            if (mode == 1) { if (arg) { g_GovWanted = TRUE; GovStart(); } else g_GovOn = 0; }
            else if (mode == 2) { g_BattStop = (arg >= 2000 && arg <= 6000) ? (LONG)arg : BATT_STOP_CD; }     // test: lower the battery stop limit at run time (0 = default again)
            RtlZeroMemory(sb, 52 * sizeof(ULONG));
            sb[0] = (ULONG)g_GovOn; sb[1] = g_GovB; sb[2] = (ULONG)g_MaxTempDc; sb[3] = (ULONG)g_GovTicks;
            for (dd = 0; dd < 4; dd++) {
                sb[4 + dd] = g_GovIdx[dd]; sb[8 + dd] = (g_GovN[dd] && g_GovIdx[dd] < g_GovN[dd]) ? g_GovF[dd][g_GovIdx[dd]] : 0; sb[12 + dd] = g_GovCeil[dd]; sb[16 + dd] = g_GovUtil[dd]; sb[36 + dd] = g_GovN[dd];
            }
            for (k = 0; k < GOV_MAXCPU; k++) sb[20 + k] = g_GovBusy[k];
            sb[40] = g_GovStat; sb[41] = g_GovErr; sb[42] = g_GovCpus; sb[43] = g_GovUps; sb[44] = GOV_PERIOD_MS; sb[45] = g_EpOn ? 1u : 0u; sb[46] = g_WdtGuard ? 1u : 0u; sb[47] = g_GovWanted ? 1u : 0u;
            sb[48] = (ULONG)g_BattCd; sb[49] = g_GovBcap; sb[50] = (ULONG)g_BattStop; sb[51] = (ULONG)g_BattHot;
            info = 52 * sizeof(ULONG); st = STATUS_SUCCESS;
        } else st = STATUS_INVALID_PARAMETER;
    }
    else if (sp->Parameters.DeviceIoControl.IoControlCode == IOCTL_DBGCAP_POLL) {
        if (sp->Parameters.DeviceIoControl.InputBufferLength >= 12 && sp->Parameters.DeviceIoControl.OutputBufferLength >= 16) {
            ULONG inb[3];
            RtlCopyMemory(inb, Irp->AssociatedIrp.SystemBuffer, 12);
            st = PollCtl(inb, (PULONG)Irp->AssociatedIrp.SystemBuffer);
            if (NT_SUCCESS(st)) info = 16;
        } else st = STATUS_INVALID_PARAMETER;
    }
    Irp->IoStatus.Status = st; Irp->IoStatus.Information = info;
    IoCompleteRequest(Irp, IO_NO_INCREMENT);
    return st;
}

VOID DcUnload(PDRIVER_OBJECT Drv)
{
    UNICODE_STRING Link = RTL_CONSTANT_STRING(L"\\DosDevices\\dbgcap");
    g_IrqKick = 0;
    KickStop();
    IrqDisconnectAll();
    FixStop();
    GovStop();
    CrumbStop();
    if (g_PollOn) { g_PollOn = 0; KeCancelTimer(&g_PollTimer); KeFlushQueuedDpcs(); PollWaitIdle(); ExSetTimerResolution(0, FALSE); }
    if (g_SetCb) g_SetCb(DcCallback, FALSE /* remove */);
    IoDeleteSymbolicLink(&Link);
    if (Drv->DeviceObject) IoDeleteDevice(Drv->DeviceObject);
    if (g_Ring) ExFreePoolWithTag(g_Ring, 'pcgD');
}

// Services\dbgcap\NoFix = 1 (set by guard.cmd nofix) skips the ITS stall fixer: ordinary runs only want the hang/overheat guard and the CPU cap, not two 1 ms polling threads and a 1 ms timer resolution.
static ULONG ReadDword(PUNICODE_STRING Reg, PWSTR Name)
{
    RTL_QUERY_REGISTRY_TABLE q[2];
    WCHAR path[260]; ULONG v = 0, def = 0, n;
    if (!Reg || !Reg->Buffer) return 0;
    n = Reg->Length / 2; if (n > 258) n = 258;
    RtlCopyMemory(path, Reg->Buffer, n * 2); path[n] = 0;
    RtlZeroMemory(q, sizeof(q));
    q[0].Flags = RTL_QUERY_REGISTRY_DIRECT; q[0].Name = Name; q[0].EntryContext = &v;
    q[0].DefaultType = REG_DWORD; q[0].DefaultData = &def; q[0].DefaultLength = sizeof(ULONG);
    if (!NT_SUCCESS(RtlQueryRegistryValues(RTL_REGISTRY_ABSOLUTE, path, q, NULL, NULL))) return 0;
    return v;
}
static BOOLEAN ReadFlag(PUNICODE_STRING Reg, PWSTR Name) { return ReadDword(Reg, Name) != 0; }

NTSTATUS DriverEntry(PDRIVER_OBJECT Drv, PUNICODE_STRING Reg)
{
    UNICODE_STRING Name = RTL_CONSTANT_STRING(L"\\Device\\dbgcap");
    UNICODE_STRING Link = RTL_CONSTANT_STRING(L"\\DosDevices\\dbgcap");
    UNICODE_STRING nCb = RTL_CONSTANT_STRING(L"DbgSetDebugPrintCallback");
    UNICODE_STRING nFl = RTL_CONSTANT_STRING(L"DbgSetDebugFilterState");
    PFN_SET_FILTER setFilter;
    PDEVICE_OBJECT Dev;
    NTSTATUS St;
    ULONG id;
    UNREFERENCED_PARAMETER(Reg);
    KeInitializeSpinLock(&g_Lock);

    g_Ring = (PUCHAR)ExAllocatePoolWithTag(NonPagedPool, RING_SIZE, 'pcgD');
    if (!g_Ring) return STATUS_INSUFFICIENT_RESOURCES;
    RtlZeroMemory(g_Ring, RING_SIZE);
    St = IoCreateDeviceSecure(Drv, 0, &Name, DEV_TYPE, FILE_DEVICE_SECURE_OPEN, FALSE, &SDDL_DEVOBJ_SYS_ALL_ADM_ALL, NULL, &Dev);
    if (!NT_SUCCESS(St)) { ExFreePoolWithTag(g_Ring, 'pcgD'); return St; }
    St = IoCreateSymbolicLink(&Link, &Name);
    if (!NT_SUCCESS(St)) { IoDeleteDevice(Dev); ExFreePoolWithTag(g_Ring, 'pcgD'); return St; }
    Drv->MajorFunction[IRP_MJ_CREATE] = DcCreateClose;
    Drv->MajorFunction[IRP_MJ_CLOSE] = DcCreateClose;
    Drv->MajorFunction[IRP_MJ_DEVICE_CONTROL] = DcIoctl;
    Drv->DriverUnload = DcUnload;
    Dev->Flags &= ~DO_DEVICE_INITIALIZING;
    g_MaxRunSec = ReadDword(Reg, L"MaxRunSec");     // Services\dbgcap\MaxRunSec = seconds (guard.cmd 5th argument); 0 = unlimited
    g_PollPassive = ReadFlag(Reg, L"PollPassive");  // Services\dbgcap\PollPassive = 1 (guard.cmd ... passive)
    g_DpPoll = ReadFlag(Reg, L"DpPoll");          // Services\dbgcap\DpPoll = 1 (guard.cmd ... dppoll): PollWork also services the data-path ext groups
    g_NoCap = ReadFlag(Reg, L"NoCap");            // Services\dbgcap\NoCap = 1 (guard.cmd ... nocap): keep the watchdog guard but leave the CPU clusters alone
    { ULONG bsv = ReadDword(Reg, L"BattStop"); if (bsv >= 2000 && bsv <= 6000) g_BattStop = (LONG)bsv; }
    { ULONG gtv = ReadDword(Reg, L"GovTemp"); if (gtv >= 500 && gtv <= 850) g_GovHot = (LONG)gtv; }
    g_GovWanted = ReadFlag(Reg, L"Gov");          // Services\dbgcap\Gov = 1 (S:\rm9\gov.flag in esp_run_prod_wifi.cmd): load-following CPU frequency governor instead of the static cap
    CrumbStart();
    if (!ReadFlag(Reg, L"NoFix")) FixStart();

    g_SetCb = (PFN_SET_CB)MmGetSystemRoutineAddress(&nCb);
    setFilter = (PFN_SET_FILTER)MmGetSystemRoutineAddress(&nFl);
    if (setFilter) for (id = 0; id < 256; id++) setFilter(id, 0xFFFFFFFF, TRUE);
    if (g_SetCb) {
        NTSTATUS s2 = g_SetCb(DcCallback, TRUE);
        char m[] = "dbgcap: callback registered, build " __DATE__ " " __TIME__ "\n";
        UNREFERENCED_PARAMETER(s2);
        PutBytes((const UCHAR *)m, sizeof(m) - 1);
        { char r[] = "dbgcap: set-callback status 0x"; UCHAR h[8]; int q; PutBytes((const UCHAR *)r, sizeof(r) - 1); for (q = 0; q < 8; q++) h[q] = (UCHAR)Hex[((ULONG)s2 >> (28 - 4 * q)) & 15]; PutBytes(h, 8); }
        { UCHAR nl = '\n'; PutBytes(&nl, 1); }
    } else {
        char m[] = "dbgcap: DbgSetDebugPrintCallback not found\n";
        PutBytes((const UCHAR *)m, sizeof(m) - 1);
    }
    return STATUS_SUCCESS;
}
