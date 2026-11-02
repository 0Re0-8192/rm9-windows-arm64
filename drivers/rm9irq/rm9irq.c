// rm9irq.sys - owns the GIC SPIs 800..811 as PnP interrupt resources and wakes the Wi-Fi poll when one fires.   KMDF; binds to the ACPI device RM9I0001 (DSDT of Mu-pcie-rp5), whose _CRS gives the translated interrupt resources.
// Background (NEXT.md 0az): LPIs never reach this VM's Windows, but the WCN7850's MSIs can be pointed at the GIC MBI frame (0x17110040) with data = INTID 800 + vector, which arrive as SPIs.
// IoConnectInterruptEx(FULLY_SPECIFIED) refuses an interrupt the caller's PDO does not own (STATUS_NOT_SUPPORTED for the PCI PDOs, tried by dbgcap), so the interrupts are claimed by this device instead.
// ISR: count + queue a DPC; DPC: set the named synchronization event \BaseNamedObjects\Rm9IrqKick, which dbgcap.sys waits on (together with a slow heartbeat) to run its Wi-Fi poll.  Diagnostics via DbgPrintEx
// ("RM9IRQ ..." lines), which dbgcap.sys captures into S:\rm9\dbgcap.txt.
#include <ntddk.h>
#include <wdf.h>

#define IRQ_MAX 16
#define KICK_NAME L"\\BaseNamedObjects\\Rm9IrqKick"
#define RLOG(...) DbgPrintEx(DPFLTR_IHVDRIVER_ID, DPFLTR_ERROR_LEVEL, __VA_ARGS__)

typedef struct _DEV_CTX {
    PKINTERRUPT Obj[IRQ_MAX];
    ULONG Vec[IRQ_MAX];
    ULONG N;
    WDFTIMER Hb;
    WDFWORKITEM Wi;
} DEV_CTX, *PDEV_CTX;
WDF_DECLARE_CONTEXT_TYPE_WITH_NAME(DEV_CTX, GetCtx)

static volatile LONG g_Cnt[IRQ_MAX];
static volatile LONG g_Kicks;
static LONG g_Shown[IRQ_MAX];
static KDPC g_Dpc;
static PKEVENT g_Kick;
static HANDLE g_KickH;

static BOOLEAN IrqIsr(PKINTERRUPT Intr, PVOID Ctx)
{
    ULONG i = (ULONG)(ULONG_PTR)Ctx;
    UNREFERENCED_PARAMETER(Intr);
    if (i < IRQ_MAX) g_Cnt[i]++;                       // diagnostic counter; a lost update on another CPU does not matter
    KeInsertQueueDpc(&g_Dpc, NULL, NULL);
    return TRUE;
}

static VOID IrqDpc(PKDPC Dpc, PVOID Ctx, PVOID A1, PVOID A2)
{
    UNREFERENCED_PARAMETER(Dpc); UNREFERENCED_PARAMETER(Ctx); UNREFERENCED_PARAMETER(A1); UNREFERENCED_PARAMETER(A2);
    g_Kicks++;
    if (g_Kick) KeSetEvent(g_Kick, IO_NO_INCREMENT, FALSE);
}

// The kick event may fail to be created in AddDevice at boot (\BaseNamedObjects does not exist yet when the ACPI device starts that early, NEXT.md 0bg): retry from a PASSIVE_LEVEL work item queued by the heartbeat.
static VOID MakeKickEvent(VOID)
{
    UNICODE_STRING nm;
    if (g_Kick) return;
    RtlInitUnicodeString(&nm, KICK_NAME);
    g_Kick = IoCreateSynchronizationEvent(&nm, &g_KickH);
    RLOG("RM9IRQ kick event %p\n", g_Kick);
}

static VOID EvtMakeEvent(WDFWORKITEM Wi)
{
    UNREFERENCED_PARAMETER(Wi);
    MakeKickEvent();
}

static VOID HbTimer(WDFTIMER Timer)
{
    PDEV_CTX c = GetCtx(WdfTimerGetParentObject(Timer));
    ULONG i; BOOLEAN changed = FALSE;
    if (!g_Kick && c->Wi) WdfWorkItemEnqueue(c->Wi);
    for (i = 0; i < c->N && i < IRQ_MAX; i++) if (g_Cnt[i] != g_Shown[i]) changed = TRUE;
    if (changed) {
        RLOG("RM9IRQ counts v%u=%d v%u=%d v%u=%d v%u=%d v%u=%d v%u=%d v%u=%d v%u=%d v%u=%d v%u=%d v%u=%d v%u=%d kicks=%d\n",
             c->Vec[0], g_Cnt[0], c->Vec[1], g_Cnt[1], c->Vec[2], g_Cnt[2], c->Vec[3], g_Cnt[3], c->Vec[4], g_Cnt[4], c->Vec[5], g_Cnt[5],
             c->Vec[6], g_Cnt[6], c->Vec[7], g_Cnt[7], c->Vec[8], g_Cnt[8], c->Vec[9], g_Cnt[9], c->Vec[10], g_Cnt[10], c->Vec[11], g_Cnt[11], g_Kicks);
        for (i = 0; i < IRQ_MAX; i++) g_Shown[i] = g_Cnt[i];
    }
}

static NTSTATUS EvtPrepare(WDFDEVICE Device, WDFCMRESLIST Raw, WDFCMRESLIST Tr)
{
    PDEV_CTX c = GetCtx(Device);
    ULONG n = WdfCmResourceListGetCount(Tr), i;
    PDEVICE_OBJECT pdo = WdfDeviceWdmGetPhysicalDevice(Device);
    UNREFERENCED_PARAMETER(Raw);
    RLOG("RM9IRQ PrepareHardware: %u resources\n", n);
    for (i = 0; i < n; i++) {
        PCM_PARTIAL_RESOURCE_DESCRIPTOR d = WdfCmResourceListGetDescriptor(Tr, i);
        IO_CONNECT_INTERRUPT_PARAMETERS p;
        NTSTATUS st; ULONG k;
        if (!d) continue;
        RLOG("RM9IRQ res %u: type %u share %u flags %x\n", i, (ULONG)d->Type, (ULONG)d->ShareDisposition, (ULONG)d->Flags);
        if (d->Type != CmResourceTypeInterrupt) continue;
        RLOG("RM9IRQ   interrupt: level %u vector %u affinity %llx\n", (ULONG)d->u.Interrupt.Level, (ULONG)d->u.Interrupt.Vector, (ULONGLONG)d->u.Interrupt.Affinity);
        if (c->N >= IRQ_MAX) break;
        k = c->N;
        // ACPI _CRS interrupt (device ACPI\RM9I0001, NEXT.md 0bd): the translated descriptor already holds the IRQL (Level), the system vector and the affinity, so connect with exactly those.
        RtlZeroMemory(&p, sizeof(p));
        p.Version = CONNECT_FULLY_SPECIFIED;
        p.FullySpecified.PhysicalDeviceObject = pdo;
        p.FullySpecified.InterruptObject = &c->Obj[k];
        p.FullySpecified.ServiceRoutine = IrqIsr;
        p.FullySpecified.ServiceContext = (PVOID)(ULONG_PTR)k;
        p.FullySpecified.SpinLock = NULL;
        p.FullySpecified.SynchronizeIrql = (KIRQL)d->u.Interrupt.Level;
        p.FullySpecified.FloatingSave = FALSE;
        p.FullySpecified.ShareVector = FALSE;
        p.FullySpecified.Vector = d->u.Interrupt.Vector;
        p.FullySpecified.Irql = (KIRQL)d->u.Interrupt.Level;
        p.FullySpecified.InterruptMode = (d->Flags & CM_RESOURCE_INTERRUPT_LATCHED) ? Latched : LevelSensitive;
        p.FullySpecified.ProcessorEnableMask = d->u.Interrupt.Affinity ? d->u.Interrupt.Affinity : 0xFF;
        p.FullySpecified.Group = 0;
        st = IoConnectInterruptEx(&p);
        RLOG("RM9IRQ connect (translated) vector %u irql %u %s -> %08x\n", (ULONG)d->u.Interrupt.Vector, (ULONG)d->u.Interrupt.Level, (d->Flags & CM_RESOURCE_INTERRUPT_LATCHED) ? "edge" : "level", (ULONG)st);
        if (NT_SUCCESS(st)) { c->Vec[k] = d->u.Interrupt.Vector; c->N++; continue; }
        c->Obj[k] = NULL;
        // The legacy IRQConfig resource of a ROOT device is not translated on ARM64: Level and Vector both hold the raw number (800), so Level is no usable IRQL.  Keep the Vector (the PnP-owned GSIV) and
        // search for an IRQL (3..12; CLOCK_LEVEL is 13) and trigger mode the HAL accepts: the first pair that works is remembered and used for the remaining lines.
        {
            static LONG s_ir = -1; static LONG s_md = -1;
            LONG md, ir; ULONG tried = 0; st = STATUS_UNSUCCESSFUL;
            for (md = 0; md < 2 && !NT_SUCCESS(st); md++) {
                for (ir = 3; ir <= 12 && !NT_SUCCESS(st); ir++) {
                    if (s_ir >= 0 && (ir != s_ir || md != s_md)) continue;
                    RtlZeroMemory(&p, sizeof(p));
                    p.Version = CONNECT_FULLY_SPECIFIED;
                    p.FullySpecified.PhysicalDeviceObject = pdo;
                    p.FullySpecified.InterruptObject = &c->Obj[k];
                    p.FullySpecified.ServiceRoutine = IrqIsr;
                    p.FullySpecified.ServiceContext = (PVOID)(ULONG_PTR)k;
                    p.FullySpecified.SpinLock = NULL;
                    p.FullySpecified.SynchronizeIrql = (KIRQL)ir;
                    p.FullySpecified.FloatingSave = FALSE;
                    p.FullySpecified.ShareVector = FALSE;
                    p.FullySpecified.Vector = d->u.Interrupt.Vector;
                    p.FullySpecified.Irql = (KIRQL)ir;
                    p.FullySpecified.InterruptMode = (md == 0) ? Latched : LevelSensitive;
                    p.FullySpecified.ProcessorEnableMask = 0xFF;
                    p.FullySpecified.Group = 0;
                    st = IoConnectInterruptEx(&p);
                    tried++;
                    if (c->N == 0 || NT_SUCCESS(st)) RLOG("RM9IRQ connect vector %u irql %d mode %s -> %08x\n", d->u.Interrupt.Vector, ir, md == 0 ? "edge" : "level", (ULONG)st);
                    if (NT_SUCCESS(st)) { s_ir = ir; s_md = md; }
                }
            }
            if (NT_SUCCESS(st)) { c->Vec[k] = d->u.Interrupt.Vector; c->N++; } else { c->Obj[k] = NULL; RLOG("RM9IRQ vector %u: %u attempts, last %08x\n", d->u.Interrupt.Vector, tried, (ULONG)st); }
        }
    }
    RLOG("RM9IRQ connected %u interrupts\n", c->N);
    WdfTimerStart(c->Hb, WDF_REL_TIMEOUT_IN_MS(1000));
    return STATUS_SUCCESS;
}

static NTSTATUS EvtRelease(WDFDEVICE Device, WDFCMRESLIST Tr)
{
    PDEV_CTX c = GetCtx(Device);
    ULONG i;
    UNREFERENCED_PARAMETER(Tr);
    WdfTimerStop(c->Hb, TRUE);
    for (i = 0; i < IRQ_MAX; i++) {
        if (c->Obj[i]) {
            IO_DISCONNECT_INTERRUPT_PARAMETERS dp;
            RtlZeroMemory(&dp, sizeof(dp));
            dp.Version = CONNECT_FULLY_SPECIFIED_GROUP;
            dp.ConnectionContext.InterruptObject = c->Obj[i];
            IoDisconnectInterruptEx(&dp);
            c->Obj[i] = NULL;
        }
    }
    c->N = 0;
    KeFlushQueuedDpcs();
    RLOG("RM9IRQ ReleaseHardware\n");
    return STATUS_SUCCESS;
}

static NTSTATUS EvtAdd(WDFDRIVER Driver, PWDFDEVICE_INIT Init)
{
    WDF_PNPPOWER_EVENT_CALLBACKS pnp;
    WDF_OBJECT_ATTRIBUTES attr;
    WDF_TIMER_CONFIG tc;
    WDF_WORKITEM_CONFIG wc;
    WDFDEVICE dev; PDEV_CTX c; NTSTATUS st;
    UNREFERENCED_PARAMETER(Driver);
    WDF_PNPPOWER_EVENT_CALLBACKS_INIT(&pnp);
    pnp.EvtDevicePrepareHardware = EvtPrepare;
    pnp.EvtDeviceReleaseHardware = EvtRelease;
    WdfDeviceInitSetPnpPowerEventCallbacks(Init, &pnp);
    WDF_OBJECT_ATTRIBUTES_INIT_CONTEXT_TYPE(&attr, DEV_CTX);
    st = WdfDeviceCreate(&Init, &attr, &dev);
    if (!NT_SUCCESS(st)) return st;
    c = GetCtx(dev);
    WDF_TIMER_CONFIG_INIT_PERIODIC(&tc, HbTimer, 1000);
    WDF_OBJECT_ATTRIBUTES_INIT(&attr);
    attr.ParentObject = dev;
    st = WdfTimerCreate(&tc, &attr, &c->Hb);
    if (!NT_SUCCESS(st)) return st;
    WDF_WORKITEM_CONFIG_INIT(&wc, EvtMakeEvent);
    wc.AutomaticSerialization = FALSE;
    WDF_OBJECT_ATTRIBUTES_INIT(&attr);
    attr.ParentObject = dev;
    st = WdfWorkItemCreate(&wc, &attr, &c->Wi);
    if (!NT_SUCCESS(st)) c->Wi = NULL;
    KeInitializeDpc(&g_Dpc, IrqDpc, NULL);
    MakeKickEvent();
    RLOG("RM9IRQ AddDevice: kick event %p (work item %08x)\n", g_Kick, (ULONG)st);
    return STATUS_SUCCESS;
}

NTSTATUS DriverEntry(PDRIVER_OBJECT Drv, PUNICODE_STRING Reg)
{
    WDF_DRIVER_CONFIG cfg;
    WDF_DRIVER_CONFIG_INIT(&cfg, EvtAdd);
    return WdfDriverCreate(Drv, Reg, WDF_NO_OBJECT_ATTRIBUTES, &cfg, WDF_NO_HANDLE);
}
