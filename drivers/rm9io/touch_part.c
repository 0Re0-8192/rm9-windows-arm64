
// ---- touch poller -------------------------------------------------------------------------------------------------------------------------------------
static volatile RM9_TOUCH_OUT g_Touch;
static volatile LONG g_TouchStop;
static HANDLE g_TouchThread;
static PVOID g_TouchThreadObj;
static PUCHAR g_Se;           // SE4 registers
static PUCHAR g_Dma;          // 4 KB non-cached contiguous (below 4 GB)
static ULONG g_DmaPa;

#define SE_RD(o)     READ_REGISTER_ULONG((PULONG)(g_Se + (o)))
#define SE_WR(o, v)  WRITE_REGISTER_ULONG((PULONG)(g_Se + (o)), (v))

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
    UCHAR F[26], V[4];
    LARGE_INTEGER Dly;
    UNREFERENCED_PARAMETER(Ctx);

    Dly.QuadPart = -50000;      // 5 ms
    g_Touch.Confirm = GoodixRd(0x2000, V, 4) ? (V[0] | (V[1] << 8) | (V[2] << 16) | ((ULONG)V[3] << 24)) : 0xFFFFFFFFu;
    while (!g_TouchStop) {
        g_Touch.Polls++;
        if (!GoodixRd(0x10308, F, 26)) {
            g_Touch.Errors++;
        } else if (F[0] != 0) {
            RtlCopyMemory((PVOID)g_Touch.Frame, F, 26);
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
    if (g_TouchThreadObj) {
        KeWaitForSingleObject(g_TouchThreadObj, Executive, KernelMode, FALSE, NULL);
        ObDereferenceObject(g_TouchThreadObj);
        g_TouchThreadObj = NULL;
    }
}

