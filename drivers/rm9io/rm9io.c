// rm9io.sys - tiny WDM driver for RedMagic 9 Pro (NX769J) Windows bring-up: read / write physical MMIO from user mode.
// Test-signed only (the phone runs Windows in Test Mode).  Device: \\.\rm9io  (SYSTEM / Administrators only).
//   IOCTL_RM9_READ   in: { UINT64 Phys; UINT32 Count }          out: Count x UINT32 (32-bit reads, 4-byte aligned, Count <= 1024)
//   IOCTL_RM9_WRITE  in: { UINT64 Phys; UINT32 Value; UINT32 Mask }   Mask = 0 / 0xFFFFFFFF: plain write; otherwise read-modify-write (Mask = bits to replace)
// Every access maps the range uncached with MmMapIoSpaceEx and is wrapped in __try; an external abort that cannot be caught still crashes Windows
// (the phone then restarts back into Android via the watchdog).
#include <ntddk.h>
#include <wdmsec.h>

#define RM9_DEVICE_TYPE 0x8F00
#define IOCTL_RM9_READ  CTL_CODE(RM9_DEVICE_TYPE, 0x800, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_RM9_WRITE CTL_CODE(RM9_DEVICE_TYPE, 0x801, METHOD_BUFFERED, FILE_ANY_ACCESS)
// Touch (Goodix BRL-D on GENI SE4 SPI).  MuChain (TOUCH.TXT, Windows boot) powers the panel IC, sets pins/clocks, maps SMMU stream 0xA3 and initialises SE4; this driver runs the SPI DMA transfers.
#define IOCTL_RM9_TOUCH_START CTL_CODE(RM9_DEVICE_TYPE, 0x802, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_RM9_TOUCH_GET   CTL_CODE(RM9_DEVICE_TYPE, 0x803, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_RM9_TOUCH_STOP  CTL_CODE(RM9_DEVICE_TYPE, 0x804, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define SE4_PHYS 0xA90000ULL
#define IOCTL_RM9_EDGES      CTL_CODE(RM9_DEVICE_TYPE, 0x805, METHOD_BUFFERED, FILE_ANY_ACCESS)

#pragma pack(push, 1)
typedef struct { UINT64 Phys; UINT32 Count; } RM9_READ_IN;
typedef struct { UINT64 Phys; UINT32 Value; UINT32 Mask; } RM9_WRITE_IN;
typedef struct {
    UINT32 Seq;          // frames with status != 0 so far
    UINT32 Polls;        // transfers attempted
    UINT32 Errors;       // failed transfers
    UINT32 Running;
    UINT32 LastTd, LastRd, LastM;   // DMA tx/rx/main IRQ status of the last failed transfer
    UINT32 Confirm;      // first poll: register 0x2000 as a LE word, 0xFFFFFFFF if the read failed
    UINT8  Frame[48];    // last frame with status != 0 (read from 0x10308: 8-byte header + 5 contacts of 8 bytes)
    UINT32 Reinits;      // SE re-initialisations done by the poller
    UINT32 Diag[12];     // SE registers at the last failure: status 0x40, clk_ctrl 0x60, if_dis 0x64, m_irq 0x610, m_cmd 0x600, dma_mode 0x258, ser_m_clk 0x48, tx_st 0xC40, rx_st 0xD40, tx_len 0xC54, rx_len 0xD54, tx_trans 0x26C
} RM9_TOUCH_OUT;
// IOCTL_RM9_EDGES: poll bit 0 of the 32-bit register at Phys as fast as possible for Ms milliseconds, count edges and record the time (us) of the first rising edges
typedef struct { UINT64 Phys; UINT32 Ms; UINT32 Mask; } RM9_EDGES_IN;
typedef struct { UINT32 Rising, Falling, Samples, ElapsedUs, HighSamples, Pad[3]; UINT32 Ts[32]; } RM9_EDGES_OUT;

#pragma pack(pop)

DRIVER_INITIALIZE DriverEntry;
DRIVER_UNLOAD Rm9Unload;
_Dispatch_type_(IRP_MJ_CREATE) _Dispatch_type_(IRP_MJ_CLOSE) DRIVER_DISPATCH Rm9CreateClose;
_Dispatch_type_(IRP_MJ_DEVICE_CONTROL) DRIVER_DISPATCH Rm9Ioctl;


// ---- touch poller -------------------------------------------------------------------------------------------------------------------------------------
static volatile RM9_TOUCH_OUT g_Touch;
static volatile LONG g_TouchStop;
static BOOLEAN g_TimerRes;
static HANDLE g_TouchThread;
static PVOID g_TouchThreadObj;
static PUCHAR g_Se;           // SE4 registers
static PUCHAR g_Dma;          // 4 KB non-cached contiguous (below 4 GB)
static ULONG g_DmaPa;

#define SE_RD(o)     READ_REGISTER_ULONG((PULONG)(g_Se + (o)))
#define SE_WR(o, v)  WRITE_REGISTER_ULONG((PULONG)(g_Se + (o)), (v))

static VOID SeSnapshot(VOID)
{
    g_Touch.Diag[0] = SE_RD(0x40);  g_Touch.Diag[1] = SE_RD(0x60);  g_Touch.Diag[2] = SE_RD(0x64);  g_Touch.Diag[3] = SE_RD(0x610);
    g_Touch.Diag[4] = SE_RD(0x600); g_Touch.Diag[5] = SE_RD(0x258); g_Touch.Diag[6] = SE_RD(0x48);  g_Touch.Diag[7] = SE_RD(0xC40);
    g_Touch.Diag[8] = SE_RD(0xD40); g_Touch.Diag[9] = SE_RD(0xC54); g_Touch.Diag[10] = SE_RD(0xD54); g_Touch.Diag[11] = SE_RD(0x26C);
}

// cancel / abort whatever the SE is doing, reset the DMA state machines, then redo geni_se_init + spi_geni_init (as MuChain GeniSpiInit)
static VOID SeReinit(VOID)
{
    ULONG T, Depth;
    SE_WR(0x604, 4U);                                    // M cancel
    for (T = 0; T < 1000 && !(SE_RD(0x610) & 0x10U); T++) { KeStallExecutionProcessor(10); }
    if (!(SE_RD(0x610) & 0x10U)) {
        SE_WR(0x604, 2U);                                // M abort
        for (T = 0; T < 1000 && !(SE_RD(0x610) & 0x20U); T++) { KeStallExecutionProcessor(10); }
    }
    SE_WR(0xC58, 1);
    SE_WR(0xD58, 1);
    KeStallExecutionProcessor(2000);
    SE_WR(0xE18, 0);
    SE_WR(0x618, 0xFFFFFFFF);
    SE_WR(0x648, 0xFFFFFFFF);
    SE_WR(0xC44, 0xFFFFFFFF);
    SE_WR(0xD44, 0xFFFFFFFF);
    SE_WR(0xE1C, 0xFFFFFFFF);
    SE_WR(0x28, SE_RD(0x28) | 0x7F);
    SE_WR(0xE30, SE_RD(0xE30) | 0xF);
    SE_WR(0x24, 0x7F);
    SE_WR(0x20, 1);
    SE_WR(0x258, SE_RD(0x258) & ~1U);
    Depth = (SE_RD(0xE24) >> 16) & 0x3F;
    if (Depth < 4) { Depth = 16; }
    SE_WR(0x810, Depth - 3);
    SE_WR(0x814, Depth - 2);
    SE_WR(0x614, SE_RD(0x614) | 0x7FC0007F);
    SE_WR(0x644, SE_RD(0x644) | 0x3E | 0x3E00 | 0x3000000);
    SE_WR(0x22C, 0);
    SE_WR(0x250, 0);
    SE_WR(0x224, 0);
    SE_WR(0x230, 0);
    SE_WR(0x24C, 0);
    SE_WR(0x25C, SE_RD(0x25C) & ~2U);
    SE_WR(0x260, 0x7F8FE);
    SE_WR(0x264, 0xFFEFE);
    SE_WR(0x284, 0x7F8FE);
    SE_WR(0x288, 0xFFEFE);
    SE_WR(0x254, 0);
    SE_WR(0x268, 4);
    SE_WR(0x7C, 0);
    SE_WR(0x48, (1U << 4) | 1U);
    g_Touch.Reinits++;
}

static BOOLEAN GeniXfer(const UCHAR *Tx, UCHAR *Rx, ULONG Len)
{
    ULONG I, T, Td = 0, Rd = 0, M = 0;
    PUCHAR Txb = g_Dma, Rxb = g_Dma + 128;
    ULONG TxPa = g_DmaPa, RxPa = g_DmaPa + 128;

    if (Len == 0 || Len > 64) {
        return FALSE;
    }
    for (I = 0; I < 128; I++) {
        Txb[I] = I < Len ? Tx[I] : 0;
        Rxb[I] = 0xEE;
    }
    KeMemoryBarrier();
    SE_WR(0xE18, 0);
    SE_WR(0x618, 0xFFFFFFFF);
    SE_WR(0x648, 0xFFFFFFFF);
    SE_WR(0xC44, 0xFFFFFFFF);
    SE_WR(0xD44, 0xFFFFFFFF);
    SE_WR(0xE1C, 0xFFFFFFFF);
    SE_WR(0x614, SE_RD(0x614) & ~(0x1U | 0x40000000U | 0x4000000U | 0x8000000U));
    SE_WR(0x258, SE_RD(0x258) | 1U);
    SE_WR(0x26C, Len);
    SE_WR(0x270, Len);
    SE_WR(0x600, 3U << 27);
    SE_WR(0xD4C, 7);
    SE_WR(0xD30, RxPa);
    SE_WR(0xD34, 0);
    SE_WR(0xD38, 0);
    SE_WR(0xD3C, Len);
    SE_WR(0xC4C, 7);
    SE_WR(0xC30, TxPa);
    SE_WR(0xC34, 0);
    SE_WR(0xC38, 1);
    SE_WR(0xC3C, Len);
    for (T = 0; T < 20000; T++) {
        Td |= SE_RD(0xC40);
        Rd |= SE_RD(0xD40);
        M |= SE_RD(0x610);
        if ((Td & 4) || (Rd & 4) || (M & 0x3300003EU)) {
            break;
        }
        if ((Td & 1) && (Rd & 1)) {
            break;
        }
        KeStallExecutionProcessor(10);
    }
    if (!(Td & 1) || !(Rd & 1) || (Td & 4) || (Rd & 4)) {
        g_Touch.LastTd = Td; g_Touch.LastRd = Rd; g_Touch.LastM = M;
        SeSnapshot();
        SE_WR(0x604, 4U);
        KeStallExecutionProcessor(2000);
        SE_WR(0xC58, 1);
        SE_WR(0xD58, 1);
        KeStallExecutionProcessor(2000);
        SE_WR(0x618, 0xFFFFFFFF);
        SE_WR(0xC44, 0xFFFFFFFF);
        SE_WR(0xD44, 0xFFFFFFFF);
        return FALSE;
    }
    for (T = 0; T < 1000 && (SE_RD(0x610) & 1U) == 0; T++) {
        KeStallExecutionProcessor(10);
    }
    SE_WR(0x618, 0xFFFFFFFF);
    SE_WR(0xC44, 0xFFFFFFFF);
    SE_WR(0xD44, 0xFFFFFFFF);
    KeMemoryBarrier();
    for (I = 0; I < Len; I++) {
        Rx[I] = Rxb[I];
    }
    return TRUE;
}

static BOOLEAN GoodixRd(ULONG Addr, UCHAR *Data, ULONG Len)
{
    UCHAR Tx[64], Rx[64];
    ULONG I;
    if (Len == 0 || Len + 8 > 64) {
        return FALSE;
    }
    RtlZeroMemory(Tx, sizeof(Tx));
    Tx[0] = 0xF1;
    Tx[1] = (UCHAR)(Addr >> 24); Tx[2] = (UCHAR)(Addr >> 16); Tx[3] = (UCHAR)(Addr >> 8); Tx[4] = (UCHAR)Addr;
    Tx[5] = Tx[6] = Tx[7] = 0xFF;
    if (!GeniXfer(Tx, Rx, 8 + Len)) {
        return FALSE;
    }
    for (I = 0; I < Len; I++) {
        Data[I] = Rx[8 + I];
    }
    return TRUE;
}

static BOOLEAN GoodixWr0(ULONG Addr)
{
    UCHAR Tx[6], Rx[6];
    Tx[0] = 0xF0;
    Tx[1] = (UCHAR)(Addr >> 24); Tx[2] = (UCHAR)(Addr >> 16); Tx[3] = (UCHAR)(Addr >> 8); Tx[4] = (UCHAR)Addr;
    Tx[5] = 0;
    return GeniXfer(Tx, Rx, 6);
}

static VOID TouchThread(PVOID Ctx)
{
    UCHAR F[48], V[4];
    LARGE_INTEGER Dly;
    UNREFERENCED_PARAMETER(Ctx);

    Dly.QuadPart = -20000;      // 2 ms; with the 1 ms system timer resolution requested in TouchStart this really is ~2 ms (15.6 ms otherwise -> 61 Hz)
    SeReinit();
    g_Touch.Confirm = GoodixRd(0x2000, V, 4) ? (V[0] | (V[1] << 8) | (V[2] << 16) | ((ULONG)V[3] << 24)) : 0xFFFFFFFFu;
    while (!g_TouchStop) {
        g_Touch.Polls++;
        if (!GoodixRd(0x10308, F, 48)) {
            g_Touch.Errors++;
            if ((g_Touch.Errors % 20) == 0) {
                SeReinit();
            }
        } else if (F[0] != 0) {
            RtlCopyMemory((PVOID)g_Touch.Frame, F, 48);
            g_Touch.Seq++;
            GoodixWr0(0x10308);
        }
        KeDelayExecutionThread(KernelMode, FALSE, &Dly);
    }
    g_Touch.Running = 0;
    PsTerminateSystemThread(STATUS_SUCCESS);
}

static NTSTATUS TouchStart(VOID)
{
    PHYSICAL_ADDRESS Lo, Hi, Sk, Se;
    NTSTATUS St;
    if (g_Touch.Running) {
        return STATUS_SUCCESS;
    }
    Se.QuadPart = SE4_PHYS;
    if (g_Se == NULL) {
        g_Se = (PUCHAR)MmMapIoSpaceEx(Se, 0x1000, PAGE_READWRITE | PAGE_NOCACHE);
        if (g_Se == NULL) {
            return STATUS_INSUFFICIENT_RESOURCES;
        }
    }
    if (g_Dma == NULL) {
        Lo.QuadPart = 0; Hi.QuadPart = 0xFFFFFFFFLL; Sk.QuadPart = 0;
        g_Dma = (PUCHAR)MmAllocateContiguousMemorySpecifyCache(PAGE_SIZE, Lo, Hi, Sk, MmNonCached);
        if (g_Dma == NULL) {
            return STATUS_INSUFFICIENT_RESOURCES;
        }
        g_DmaPa = (ULONG)MmGetPhysicalAddress(g_Dma).QuadPart;
    }
    RtlZeroMemory((PVOID)&g_Touch, sizeof(g_Touch));
    g_TouchStop = 0;
    g_Touch.Running = 1;
    if (!g_TimerRes) {
        ExSetTimerResolution(10000, TRUE);
        g_TimerRes = TRUE;
    }
    St = PsCreateSystemThread(&g_TouchThread, THREAD_ALL_ACCESS, NULL, NULL, NULL, TouchThread, NULL);
    if (!NT_SUCCESS(St)) {
        g_Touch.Running = 0;
        return St;
    }
    ObReferenceObjectByHandle(g_TouchThread, THREAD_ALL_ACCESS, NULL, KernelMode, &g_TouchThreadObj, NULL);
    ZwClose(g_TouchThread);
    g_TouchThread = NULL;
    return STATUS_SUCCESS;
}

static VOID TouchStopAndWait(VOID)
{
    g_TouchStop = 1;
    if (g_TimerRes) {
        ExSetTimerResolution(10000, FALSE);
        g_TimerRes = FALSE;
    }
    if (g_TouchThreadObj) {
        KeWaitForSingleObject(g_TouchThreadObj, Executive, KernelMode, FALSE, NULL);
        ObDereferenceObject(g_TouchThreadObj);
        g_TouchThreadObj = NULL;
    }
}

static NTSTATUS EdgeScan(RM9_EDGES_IN *In, RM9_EDGES_OUT *Out)
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

static NTSTATUS Rm9Complete(PIRP Irp, NTSTATUS St, ULONG_PTR Info)
{
    Irp->IoStatus.Status = St;
    Irp->IoStatus.Information = Info;
    IoCompleteRequest(Irp, IO_NO_INCREMENT);
    return St;
}

NTSTATUS Rm9CreateClose(PDEVICE_OBJECT Dev, PIRP Irp)
{
    UNREFERENCED_PARAMETER(Dev);
    return Rm9Complete(Irp, STATUS_SUCCESS, 0);
}

NTSTATUS Rm9Ioctl(PDEVICE_OBJECT Dev, PIRP Irp)
{
    PIO_STACK_LOCATION Sp = IoGetCurrentIrpStackLocation(Irp);
    ULONG Code = Sp->Parameters.DeviceIoControl.IoControlCode;
    ULONG InLen = Sp->Parameters.DeviceIoControl.InputBufferLength;
    ULONG OutLen = Sp->Parameters.DeviceIoControl.OutputBufferLength;
    PVOID Buf = Irp->AssociatedIrp.SystemBuffer;
    NTSTATUS St = STATUS_INVALID_DEVICE_REQUEST;
    ULONG_PTR Info = 0;
    UNREFERENCED_PARAMETER(Dev);

    if (Code == IOCTL_RM9_READ && InLen >= sizeof(RM9_READ_IN)) {
        RM9_READ_IN In = *(RM9_READ_IN *)Buf;
        if (In.Count == 0 || In.Count > 1024 || (In.Phys & 3) || OutLen < In.Count * 4) {
            St = STATUS_INVALID_PARAMETER;
        } else {
            PHYSICAL_ADDRESS Pa;
            PVOID Va;
            Pa.QuadPart = (LONGLONG)In.Phys;
            Va = MmMapIoSpaceEx(Pa, In.Count * 4, PAGE_READWRITE | PAGE_NOCACHE);
            if (Va == NULL) {
                St = STATUS_INSUFFICIENT_RESOURCES;
            } else {
                __try {
                    ULONG i;
                    for (i = 0; i < In.Count; i++) {
                        ((PULONG)Buf)[i] = READ_REGISTER_ULONG((PULONG)Va + i);
                    }
                    St = STATUS_SUCCESS;
                    Info = In.Count * 4;
                } __except (EXCEPTION_EXECUTE_HANDLER) {
                    St = GetExceptionCode();
                }
                MmUnmapIoSpace(Va, In.Count * 4);
            }
        }
    } else if (Code == IOCTL_RM9_WRITE && InLen >= sizeof(RM9_WRITE_IN)) {
        RM9_WRITE_IN In = *(RM9_WRITE_IN *)Buf;
        if (In.Phys & 3) {
            St = STATUS_INVALID_PARAMETER;
        } else {
            PHYSICAL_ADDRESS Pa;
            PVOID Va;
            Pa.QuadPart = (LONGLONG)In.Phys;
            Va = MmMapIoSpaceEx(Pa, 4, PAGE_READWRITE | PAGE_NOCACHE);
            if (Va == NULL) {
                St = STATUS_INSUFFICIENT_RESOURCES;
            } else {
                __try {
                    if (In.Mask == 0 || In.Mask == 0xFFFFFFFFu) {
                        WRITE_REGISTER_ULONG((PULONG)Va, In.Value);
                    } else {
                        ULONG Old = READ_REGISTER_ULONG((PULONG)Va);
                        WRITE_REGISTER_ULONG((PULONG)Va, (Old & ~In.Mask) | (In.Value & In.Mask));
                    }
                    St = STATUS_SUCCESS;
                } __except (EXCEPTION_EXECUTE_HANDLER) {
                    St = GetExceptionCode();
                }
                MmUnmapIoSpace(Va, 4);
            }
        }
    }
    if (Code == IOCTL_RM9_EDGES) {
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
    else if (Code == IOCTL_RM9_TOUCH_START) {
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
    return Rm9Complete(Irp, St, Info);
}

VOID Rm9Unload(PDRIVER_OBJECT Drv)
{
    UNICODE_STRING Link = RTL_CONSTANT_STRING(L"\\DosDevices\\rm9io");
    TouchStopAndWait();
    IoDeleteSymbolicLink(&Link);
    if (Drv->DeviceObject) {
        IoDeleteDevice(Drv->DeviceObject);
    }
}

NTSTATUS DriverEntry(PDRIVER_OBJECT Drv, PUNICODE_STRING Reg)
{
    UNICODE_STRING Name = RTL_CONSTANT_STRING(L"\\Device\\rm9io");
    UNICODE_STRING Link = RTL_CONSTANT_STRING(L"\\DosDevices\\rm9io");
    PDEVICE_OBJECT Dev;
    NTSTATUS St;
    UNREFERENCED_PARAMETER(Reg);

    St = IoCreateDeviceSecure(Drv, 0, &Name, RM9_DEVICE_TYPE, FILE_DEVICE_SECURE_OPEN, FALSE,
                              &SDDL_DEVOBJ_SYS_ALL_ADM_ALL, NULL, &Dev);
    if (!NT_SUCCESS(St)) {
        return St;
    }
    St = IoCreateSymbolicLink(&Link, &Name);
    if (!NT_SUCCESS(St)) {
        IoDeleteDevice(Dev);
        return St;
    }
    Drv->MajorFunction[IRP_MJ_CREATE] = Rm9CreateClose;
    Drv->MajorFunction[IRP_MJ_CLOSE] = Rm9CreateClose;
    Drv->MajorFunction[IRP_MJ_DEVICE_CONTROL] = Rm9Ioctl;
    Drv->DriverUnload = Rm9Unload;
    Dev->Flags &= ~DO_DEVICE_INITIALIZING;
    return STATUS_SUCCESS;
}
