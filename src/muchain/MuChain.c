/** @file MuChain: arm the GH watchdog, then chainload the Windows boot manager
    from the ESP partition, logging progress into the RAM log.

    Safety net: the watchdog is armed BEFORE the chainload; if Windows hangs or
    never returns, the SoC resets -> crash dump -> RAM-log capture -> Android.

    Progress markers (all via DEBUG_ERROR so they land in the RAM console):
      - every SimpleFileSystem volume probed for \EFI\Microsoft\Boot\bootmgfw.efi
      - LoadImage / StartImage status
      - Block IO ReadBlocks calls on logical partitions (rate limited), tagged
        by partition size, so we can see ESP / Windows partition accesses
      - ExitBootServices (== winload finished loading the kernel)
**/
#include <Uefi.h>
#include <Library/UefiApplicationEntryPoint.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiLib.h>
#include <Library/DebugLib.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/DevicePathLib.h>
#include <Library/ArmSmcLib.h>
#include <Library/PrintLib.h>
#include <Pi/PiDxeCis.h>
#include <Library/DxeServicesTableLib.h>
#include <Protocol/PartitionInfo.h>
#include <Library/UefiRuntimeServicesTableLib.h>
#include <Protocol/BlockIo.h>
#include <Protocol/LoadedImage.h>
#include <Protocol/SimpleFileSystem.h>
#include <Guid/FileInfo.h>

STATIC EFI_STATUS UfsQueryFlag (IN UINT64 Base, IN UINT8 Opcode, IN UINT8 Idn, OUT UINT8 *Val, OUT UINT8 *RespCode);
STATIC EFI_PHYSICAL_ADDRESS mUfsUcd = 0;   // DMA buffer for UFS queries, allocated early (see UfsQueryFlag)

#define WDT_MS          30000
#define MAX_HOOKS       512
STATIC BOOLEAN mInEbs = FALSE;
#define LOG_FIRST_N     24
#define LOG_EVERY_N     512

typedef struct {
  EFI_BLOCK_IO_PROTOCOL  *Block;
  EFI_BLOCK_READ         OrigRead;
  UINT64                 LastBlock;
  BOOLEAN                Logical;
  UINT64                 Count;
  UINT64                 Blocks;
} HOOK;

#include <Protocol/GraphicsOutput.h>

//
// Framebuffer snapshots: saved as top-down 32bpp BMP onto the volume MuChain
// was loaded from (logdump FAT), so the screen can be inspected after the
// watchdog reset.  Driven by a periodic timer event.
//
STATIC EFI_HANDLE   mSelfVolume = NULL;
STATIC BOOLEAN      mLongRun    = FALSE;  // \LONGRUN.TXT: disable the GH watchdog at EBS
STATIC BOOLEAN      mWdtKeep    = FALSE;  // LONGRUN without \NOKEEP.TXT: keep the GH watchdog armed at EBS (dbgcap.sys pings it once Windows is up)
STATIC BOOLEAN      mEpssCapOff = FALSE;  // \NOCAP.TXT: leave the CPU clusters at the boot-time maximum
STATIC VOID EpssCapApply (IN BOOLEAN FirstCall);
STATIC BOOLEAN      mNoWp       = FALSE;  // \NOWP.TXT present: do not set fPowerOnWPEn at EBS
STATIC BOOLEAN      mNoBoot     = TRUE;   // fail safe: stays TRUE until NOBOOT.TXT is positively known to be absent
STATIC UINTN        mTicks      = 0;
STATIC CONST UINTN  mSnapAtTick[] = { 5, 14, 26, 40 };
STATIC UINTN        mSnapIndex  = 0;

#pragma pack(1)
typedef struct {
  UINT16 Type; UINT32 Size; UINT16 R1; UINT16 R2; UINT32 OffBits;
  UINT32 HdrSize; INT32 Width; INT32 Height; UINT16 Planes; UINT16 Bpp;
  UINT32 Compression; UINT32 ImageSize; INT32 Xppm; INT32 Yppm; UINT32 Used; UINT32 Important;
} BMP_HDR;
#pragma pack()

STATIC VOID
SaveSnapshot (IN UINTN Index)
{
  EFI_STATUS                       Status;
  EFI_GRAPHICS_OUTPUT_PROTOCOL     *Gop = NULL;
  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL  *Fs = NULL;
  EFI_FILE_PROTOCOL                *Root = NULL;
  EFI_FILE_PROTOCOL                *File = NULL;
  CHAR16                           Name[16];
  BMP_HDR                          H;
  UINTN                            Size;
  UINT32                           W, Ht, Stride, Row;
  UINT8                            *Fb;

  if (mSelfVolume == NULL ||
      EFI_ERROR (gBS->LocateProtocol (&gEfiGraphicsOutputProtocolGuid, NULL, (VOID **)&Gop)) ||
      Gop == NULL || Gop->Mode == NULL || Gop->Mode->Info == NULL) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] snap%lu: no GOP/volume\n", (UINT64)Index));
    return;
  }
  W      = Gop->Mode->Info->HorizontalResolution;
  Ht     = Gop->Mode->Info->VerticalResolution;
  Stride = Gop->Mode->Info->PixelsPerScanLine;
  Fb     = (UINT8 *)(UINTN)Gop->Mode->FrameBufferBase;

  Status = gBS->HandleProtocol (mSelfVolume, &gEfiSimpleFileSystemProtocolGuid, (VOID **)&Fs);
  if (!EFI_ERROR (Status)) {
    Status = Fs->OpenVolume (Fs, &Root);
  }
  if (!EFI_ERROR (Status)) {
    UnicodeSPrint (Name, sizeof (Name), L"SNAP%lu.BMP", (UINT64)Index);
    Status = Root->Open (Root, &File, Name, EFI_FILE_MODE_READ | EFI_FILE_MODE_WRITE | EFI_FILE_MODE_CREATE, 0);
  }
  if (EFI_ERROR (Status)) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] snap%lu: open failed %r\n", (UINT64)Index, Status));
    return;
  }

  ZeroMem (&H, sizeof (H));
  H.Type = 0x4D42; H.OffBits = sizeof (H); H.HdrSize = 40;
  H.Width = (INT32)W; H.Height = -(INT32)Ht; H.Planes = 1; H.Bpp = 32;
  H.ImageSize = W * Ht * 4; H.Size = sizeof (H) + H.ImageSize;
  Size = sizeof (H);
  File->Write (File, &Size, &H);
  for (Row = 0; Row < Ht; Row++) {
    Size = (UINTN)W * 4;
    Status = File->Write (File, &Size, Fb + (UINTN)Row * Stride * 4);
    if (EFI_ERROR (Status)) {
      break;
    }
  }
  File->Flush (File);
  File->Close (File);
  Root->Close (Root);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] snap%lu saved %ux%u stride=%u fmt=%u: %r\n",
          (UINT64)Index, W, Ht, Stride, (UINT32)Gop->Mode->Info->PixelFormat, Status));
}

STATIC VOID EFIAPI
SnapTimer (IN EFI_EVENT Event, IN VOID *Context)
{
  mTicks++;
  *(volatile UINT32 *)(UINTN)0xD7FF0440ULL = (UINT32)mTicks;   // heartbeat: seconds alive (read back after the reset)
  if (mTicks < (mNoBoot ? 12 : 180)) {
    // keep the GH watchdog (hardware-capped at ~32 s) fed while UEFI is alive; if this timer stops (hang) it still bites
    ARM_SMC_ARGS Pa = { 0 };
    Pa.Arg0 = 0x86000007U;   // GH_WDT_PING
    ArmCallSmc (&Pa);
  }
  if (mSnapIndex < ARRAY_SIZE (mSnapAtTick) && mTicks == mSnapAtTick[mSnapIndex]) {
    mSnapIndex++;
    SaveSnapshot (mSnapIndex);
  }
}

STATIC HOOK                 mHooks[MAX_HOOKS];
STATIC UINTN                mHookCount = 0;
STATIC EFI_EXIT_BOOT_SERVICES mOrigExitBs = NULL;

STATIC VOID
ArmWatchdog (IN UINT32 Ms)
{
  ARM_SMC_ARGS Args = { 0 };
  INT64        S;

  Args.Arg0 = 0x86000005U;  // GH_WDT_CONTROL
  Args.Arg1 = 2;            // DISABLE
  ArmCallSmc (&Args);
  S = (INT64)Args.Arg0;
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] GH_WDT DISABLE ret=%ld\n", S));
  if (S == 0) {
    ZeroMem (&Args, sizeof (Args));
    Args.Arg0 = 0x86000008U;  // GH_WDT_SET_TIME
    Args.Arg1 = Ms;
    Args.Arg2 = Ms;
    ArmCallSmc (&Args);
    S = (INT64)Args.Arg0;
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] GH_WDT SET_TIME(%u ms) ret=%ld\n", Ms, S));
  }
  if (S == 0) {
    ZeroMem (&Args, sizeof (Args));
    Args.Arg0 = 0x86000005U;
    Args.Arg1 = 3;            // ENABLE
    ArmCallSmc (&Args);
    S = (INT64)Args.Arg0;
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] GH_WDT ENABLE ret=%ld\n", S));
  }
  if (S == 0) {
    ZeroMem (&Args, sizeof (Args));
    Args.Arg0 = 0x86000007U;  // GH_WDT_PING
    ArmCallSmc (&Args);
    S = (INT64)Args.Arg0;
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] GH_WDT PING ret=%ld\n", S));
  }
}

STATIC EFI_STATUS EFIAPI
HookRead (
  IN  EFI_BLOCK_IO_PROTOCOL  *This,
  IN  UINT32                 MediaId,
  IN  EFI_LBA                Lba,
  IN  UINTN                  BufferSize,
  OUT VOID                   *Buffer
  )
{
  UINTN Index;

  for (Index = 0; Index < mHookCount; Index++) {
    if (mHooks[Index].Block == This) {
      HOOK *H = &mHooks[Index];
      H->Count++;
      EFI_STATUS Rs;
      H->Blocks += BufferSize / This->Media->BlockSize;
      Rs = H->OrigRead (This, MediaId, Lba, BufferSize, Buffer);
      if (H->Count <= LOG_FIRST_N || (H->Count % LOG_EVERY_N) == 0 || EFI_ERROR (Rs) ||
          (!H->Logical && Lba >= 28078888ULL && Lba <= 61521886ULL)) {
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] %a(last=0x%lx) #%lu lba=0x%lx bytes=%lu -> %r\n",
                H->Logical ? "PARTREAD" : "DISKREAD", H->LastBlock, H->Count, (UINT64)Lba, (UINT64)BufferSize, Rs));
      }
      return Rs;
    }
  }
  return EFI_DEVICE_ERROR;
}

STATIC VOID
HookAllPartitions (VOID)
{
  EFI_HANDLE *Handles = NULL;
  UINTN      Count = 0;
  UINTN      Index;

  if (EFI_ERROR (gBS->LocateHandleBuffer (ByProtocol, &gEfiBlockIoProtocolGuid, NULL, &Count, &Handles))) {
    return;
  }
  for (Index = 0; Index < Count && mHookCount < MAX_HOOKS; Index++) {
    EFI_BLOCK_IO_PROTOCOL *B = NULL;
    if (EFI_ERROR (gBS->HandleProtocol (Handles[Index], &gEfiBlockIoProtocolGuid, (VOID **)&B)) || B == NULL || B->Media == NULL) {
      continue;
    }
    if (!B->Media->MediaPresent) {
      continue;
    }
    mHooks[mHookCount].Logical   = B->Media->LogicalPartition;
    mHooks[mHookCount].Block     = B;
    mHooks[mHookCount].OrigRead  = B->ReadBlocks;
    mHooks[mHookCount].LastBlock = B->Media->LastBlock;
    B->ReadBlocks = HookRead;
    mHookCount++;
  }
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] hooked %lu logical partitions\n", (UINT64)mHookCount));
  FreePool (Handles);
}

STATIC VOID
DumpHookStats (IN CONST CHAR8 *Why)
{
  UINTN Index;
  for (Index = 0; Index < mHookCount; Index++) {
    if (mHooks[Index].Count != 0) {
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] %a: part(last=0x%lx) reads=%lu blocks=%lu\n",
              Why, mHooks[Index].LastBlock, mHooks[Index].Count, mHooks[Index].Blocks));
    }
  }
}

STATIC EFI_STATUS EFIAPI
HookExitBs (IN EFI_HANDLE ImageHandle, IN UINTN MapKey)
{
  *(volatile UINT32 *)(UINTN)0xD7FF0404ULL = 0x21534245U;   // "EBS!"
  mInEbs = TRUE;
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] *** ExitBootServices called by the OS loader ***\n"));
  DumpHookStats ("at-EBS");
  if (!mNoWp) {
    // C: write-protect LUN1-4 (boot chain) until the next power cycle; the UFS device clears it on reset.
    UINT8      V1 = 0xFF, R1 = 0xFF, V2 = 0xFF, R2 = 0xFF;
    EFI_STATUS Q1 = UfsQueryFlag (0x1D84000ULL, 6, 3, &V1, &R1);
    EFI_STATUS Q2 = UfsQueryFlag (0x1D84000ULL, 5, 3, &V2, &R2);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] EBS: SET_FLAG fPowerOnWPEn %r (qresp 0x%x), READ_FLAG %r flag=%u\n", Q1, R1, Q2, V2));
    *(volatile UINT32 *)(UINTN)0xD7FF042CULL = 0x57500000U | ((UINT32)V2 << 8) | (UINT32)(EFI_ERROR (Q1) ? 1 : 0);   // "WP" + flag
  } else {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] EBS: NOWP.TXT present, fPowerOnWPEn NOT set\n"));
  }
  EpssCapApply (FALSE);     // again, in case anything touched the performance states since MuChain started
  if (mLongRun && !mWdtKeep) {
    ARM_SMC_ARGS Wa = { 0 };
    Wa.Arg0 = 0x86000005U;   // GH_WDT_CONTROL
    Wa.Arg1 = 2;             // DISABLE
    ArmCallSmc (&Wa);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] EBS: LONGRUN: GH_WDT DISABLE ret=%ld (no watchdog from here on)\n", (INT64)Wa.Arg0));
  } else if (mLongRun) {
    // keep-alive: leave the GH watchdog armed and give Windows a fresh ~31 s.  dbgcap.sys (started by run.cmd's guard.cmd ~8 s after the kernel starts) takes over the pinging;
    // if it never does, or Windows freezes later, the phone resets itself instead of idling hot.  NOKEEP.TXT restores the old "watchdog off at EBS" behaviour.
    ARM_SMC_ARGS Wp = { 0 };
    Wp.Arg0 = 0x86000007U;   // GH_WDT_PING
    ArmCallSmc (&Wp);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] EBS: LONGRUN keep-alive: GH_WDT left armed, PING ret=%ld\n", (INT64)Wp.Arg0));
  }
  gBS->ExitBootServices = mOrigExitBs;
  gBS->Hdr.CRC32 = 0;
  gBS->CalculateCrc32 (gBS, gBS->Hdr.HeaderSize, &gBS->Hdr.CRC32);
  {
    EFI_STATUS Es = mOrigExitBs (ImageHandle, MapKey);
    UINT64     Cnt;
    __asm__ volatile ("mrs %0, cntvct_el0" : "=r" (Cnt));
    if (!EFI_ERROR (Es)) {
      *(volatile UINT32 *)(UINTN)0xD7FF0408ULL = 0x4B4F4245U;   // "EBOK"
      *(volatile UINT64 *)(UINTN)0xD7FF0410ULL = Cnt;
    } else {
      *(volatile UINT32 *)(UINTN)0xD7FF0408ULL = 0x4C494645U;   // "EFIL" (EBS failed, retry follows)
    }
    return Es;
  }
}

//
// UEFI service tracing: log what the boot manager calls so a hang can be
// located from the RAM log (last logged call = where it stopped).
//
STATIC UINTN                  mCalls = 0;

#define MARKSVC(code, arg)                                                       \
  do {                                                                           \
    *(volatile UINT32 *)(UINTN)0xD7FF0420ULL = ((UINT32)(code) << 24) | ((UINT32)(arg) & 0xFFFFFF); \
    *(volatile UINT32 *)(UINTN)0xD7FF0424ULL = *(volatile UINT32 *)(UINTN)0xD7FF0424ULL + 1;        \
  } while (0)
#define TRACE(...)  do { if (!mInEbs && mCalls++ < 4000) { DEBUG ((DEBUG_ERROR, __VA_ARGS__)); } } while (0)

STATIC EFI_HANDLE_PROTOCOL    mOrigHandleProtocol;
STATIC EFI_LOCATE_PROTOCOL    mOrigLocateProtocol;
STATIC EFI_OPEN_PROTOCOL      mOrigOpenProtocol;
STATIC EFI_LOCATE_HANDLE_BUFFER mOrigLocateHandleBuffer;
STATIC EFI_GET_MEMORY_MAP     mOrigGetMemoryMap;
STATIC EFI_STALL              mOrigStall;
STATIC EFI_WAIT_FOR_EVENT     mOrigWaitForEvent;
STATIC EFI_CHECK_EVENT        mOrigCheckEvent;
STATIC EFI_GET_VARIABLE       mOrigGetVariable;
STATIC EFI_SET_VARIABLE       mOrigSetVariable;
STATIC EFI_TEXT_STRING        mOrigOutputString;
STATIC EFI_INPUT_READ_KEY     mOrigReadKey;
STATIC UINTN                  mCheckN = 0, mStallN = 0, mKeyN = 0;

STATIC EFI_STATUS EFIAPI
TrHandleProtocol (IN EFI_HANDLE H, IN EFI_GUID *P, OUT VOID **I)
{
  MARKSVC (1, 0);
  EFI_STATUS S = mOrigHandleProtocol (H, P, I);
  TRACE ("[TR] HandleProtocol %g -> %r\n", P, S);
  return S;
}

STATIC EFI_STATUS EFIAPI
TrLocateProtocol (IN EFI_GUID *P, IN VOID *R, OUT VOID **I)
{
  MARKSVC (2, 0);
  EFI_STATUS S = mOrigLocateProtocol (P, R, I);
  TRACE ("[TR] LocateProtocol %g -> %r\n", P, S);
  return S;
}

STATIC EFI_STATUS EFIAPI
TrOpenProtocol (IN EFI_HANDLE H, IN EFI_GUID *P, OUT VOID **I, IN EFI_HANDLE A, IN EFI_HANDLE C, IN UINT32 At)
{
  MARKSVC (3, 0);
  EFI_STATUS S = mOrigOpenProtocol (H, P, I, A, C, At);
  if (!CompareGuid (P, &gEfiDevicePathProtocolGuid) && !CompareGuid (P, &gEfiBlockIoProtocolGuid) &&
      !CompareGuid (P, &gEfiPartitionInfoProtocolGuid)) {
    TRACE ("[TR] OpenProtocol %g attr=%x -> %r\n", P, At, S);
  } else if (CompareGuid (P, &gEfiBlockIoProtocolGuid) && !EFI_ERROR (S) && I != NULL && *I != NULL) {
    EFI_BLOCK_IO_PROTOCOL *B = (EFI_BLOCK_IO_PROTOCOL *)*I;
    if (B->Media != NULL && B->Media->LogicalPartition) {
      STATIC UINTN BioN = 0;
      if (BioN++ < 200) {
        TRACE ("[TR] OpenProtocol BlockIo(part) last=0x%lx bs=%u\n", (UINT64)B->Media->LastBlock, B->Media->BlockSize);
      }
    }
  }
  return S;
}

STATIC EFI_STATUS EFIAPI
TrLocateHandleBuffer (IN EFI_LOCATE_SEARCH_TYPE T, IN EFI_GUID *P, IN VOID *K, IN OUT UINTN *N, OUT EFI_HANDLE **B)
{
  MARKSVC (4, 0);
  EFI_STATUS S = mOrigLocateHandleBuffer (T, P, K, N, B);
  TRACE ("[TR] LocateHandleBuffer %g -> %r n=%lu\n", P, S, (UINT64)(N != NULL ? *N : 0));
  return S;
}

STATIC EFI_STATUS EFIAPI
TrGetMemoryMap (IN OUT UINTN *Sz, OUT EFI_MEMORY_DESCRIPTOR *M, OUT UINTN *Key, OUT UINTN *DSz, OUT UINT32 *DV)
{
  MARKSVC (5, 0);
  EFI_STATUS S = mOrigGetMemoryMap (Sz, M, Key, DSz, DV);
  TRACE ("[TR] GetMemoryMap -> %r size=%lu\n", S, (UINT64)(Sz != NULL ? *Sz : 0));
  return S;
}

STATIC EFI_STATUS EFIAPI
TrStall (IN UINTN Us)
{
  MARKSVC (6, Us);
  if ((mStallN++ % 2000) == 0) {
    TRACE ("[TR] Stall(%lu) #%lu\n", (UINT64)Us, (UINT64)mStallN);
  }
  return mOrigStall (Us);
}

STATIC EFI_STATUS EFIAPI
TrWaitForEvent (IN UINTN N, IN EFI_EVENT *E, OUT UINTN *Idx)
{
  MARKSVC (7, 0);
  TRACE ("[TR] WaitForEvent n=%lu ...\n", (UINT64)N);
  return mOrigWaitForEvent (N, E, Idx);
}

STATIC EFI_STATUS EFIAPI
TrCheckEvent (IN EFI_EVENT E)
{
  MARKSVC (8, 0);
  if ((mCheckN++ % 5000) == 0) {
    TRACE ("[TR] CheckEvent #%lu\n", (UINT64)mCheckN);
  }
  return mOrigCheckEvent (E);
}

STATIC EFI_STATUS EFIAPI
TrGetVariable (IN CHAR16 *N, IN EFI_GUID *G, OUT UINT32 *A, IN OUT UINTN *Sz, OUT VOID *D)
{
  MARKSVC (20, 0);
  EFI_STATUS S = mOrigGetVariable (N, G, A, Sz, D);
  TRACE ("[TR] GetVariable %s %g -> %r\n", N, G, S);
  return S;
}

STATIC EFI_STATUS EFIAPI
TrSetVariable (IN CHAR16 *N, IN EFI_GUID *G, IN UINT32 A, IN UINTN Sz, IN VOID *D)
{
  MARKSVC (21, 0);
  EFI_STATUS S = mOrigSetVariable (N, G, A, Sz, D);
  TRACE ("[TR] SetVariable %s %g size=%lu -> %r\n", N, G, (UINT64)Sz, S);
  return S;
}

STATIC EFI_STATUS EFIAPI
TrOutputString (IN EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *This, IN CHAR16 *Str)
{
  MARKSVC (22, 0);
  TRACE ("[TR] ConOut: %s\n", Str);
  return mOrigOutputString (This, Str);
}

STATIC EFI_STATUS EFIAPI
TrReadKey (IN EFI_SIMPLE_TEXT_INPUT_PROTOCOL *This, OUT EFI_INPUT_KEY *Key)
{
  MARKSVC (23, 0);
  EFI_STATUS S = mOrigReadKey (This, Key);
  if ((mKeyN++ % 2000) == 0 || !EFI_ERROR (S)) {
    TRACE ("[TR] ReadKeyStroke #%lu -> %r\n", (UINT64)mKeyN, S);
  }
  return S;
}

STATIC EFI_ALLOCATE_PAGES       mOrigAllocatePages;
STATIC EFI_ALLOCATE_POOL        mOrigAllocatePool;
STATIC EFI_FREE_PAGES           mOrigFreePages;
STATIC EFI_CREATE_EVENT         mOrigCreateEvent;
STATIC EFI_CREATE_EVENT_EX      mOrigCreateEventEx;
STATIC EFI_SET_TIMER            mOrigSetTimer;
STATIC EFI_SET_WATCHDOG_TIMER   mOrigSetWatchdog;
STATIC EFI_INSTALL_CONFIGURATION_TABLE mOrigInstallCfg;
STATIC EFI_CONNECT_CONTROLLER   mOrigConnect;
STATIC EFI_IMAGE_START          mOrigStartImage;
STATIC EFI_IMAGE_LOAD           mOrigLoadImage;

STATIC EFI_STATUS EFIAPI
TrAllocatePages (IN EFI_ALLOCATE_TYPE T, IN EFI_MEMORY_TYPE M, IN UINTN Pg, IN OUT EFI_PHYSICAL_ADDRESS *Addr)
{
  MARKSVC (9, 0);
  EFI_STATUS S;
  TRACE ("[TR] AllocatePages type=%u mem=%u pages=%lu addr=0x%lx ...\n", (UINT32)T, (UINT32)M, (UINT64)Pg, (UINT64)(Addr != NULL ? *Addr : 0));
  S = mOrigAllocatePages (T, M, Pg, Addr);
  TRACE ("[TR] AllocatePages -> %r addr=0x%lx\n", S, (UINT64)(Addr != NULL ? *Addr : 0));
  return S;
}

STATIC EFI_STATUS EFIAPI
TrAllocatePool (IN EFI_MEMORY_TYPE M, IN UINTN Sz, OUT VOID **B)
{
  MARKSVC (10, 0);
  EFI_STATUS S = mOrigAllocatePool (M, Sz, B);
  STATIC UINTN PoolN = 0;
  if (PoolN++ < 30 || (PoolN % 20000) == 0) {
    TRACE ("[TR] AllocatePool #%lu mem=%u size=%lu -> %r\n", (UINT64)PoolN, (UINT32)M, (UINT64)Sz, S);
  }
  return S;
}

STATIC EFI_STATUS EFIAPI
TrFreePages (IN EFI_PHYSICAL_ADDRESS A, IN UINTN Pg)
{
  MARKSVC (11, 0);
  EFI_STATUS S = mOrigFreePages (A, Pg);
  TRACE ("[TR] FreePages 0x%lx %lu -> %r\n", (UINT64)A, (UINT64)Pg, S);
  return S;
}

STATIC EFI_STATUS EFIAPI
TrCreateEvent (IN UINT32 Ty, IN EFI_TPL Tpl, IN EFI_EVENT_NOTIFY Fn, IN VOID *Ctx, OUT EFI_EVENT *E)
{
  MARKSVC (12, 0);
  EFI_STATUS S = mOrigCreateEvent (Ty, Tpl, Fn, Ctx, E);
  TRACE ("[TR] CreateEvent type=%x tpl=%lu -> %r\n", Ty, (UINT64)Tpl, S);
  return S;
}

STATIC EFI_STATUS EFIAPI
TrCreateEventEx (IN UINT32 Ty, IN EFI_TPL Tpl, IN EFI_EVENT_NOTIFY Fn, IN CONST VOID *Ctx, IN CONST EFI_GUID *G, OUT EFI_EVENT *E)
{
  MARKSVC (13, 0);
  EFI_STATUS S = mOrigCreateEventEx (Ty, Tpl, Fn, Ctx, G, E);
  TRACE ("[TR] CreateEventEx type=%x -> %r\n", Ty, S);
  return S;
}

STATIC EFI_STATUS EFIAPI
TrSetTimer (IN EFI_EVENT E, IN EFI_TIMER_DELAY Ty, IN UINT64 T)
{
  MARKSVC (14, 0);
  EFI_STATUS S = mOrigSetTimer (E, Ty, T);
  TRACE ("[TR] SetTimer type=%u t=%lu -> %r\n", (UINT32)Ty, T, S);
  return S;
}

STATIC EFI_STATUS EFIAPI
TrSetWatchdog (IN UINTN T, IN UINT64 C, IN UINTN Ds, IN CHAR16 *D)
{
  MARKSVC (15, 0);
  TRACE ("[TR] SetWatchdogTimer timeout=%lu\n", (UINT64)T);
  return mOrigSetWatchdog (T, C, Ds, D);
}

STATIC EFI_STATUS EFIAPI
TrInstallCfg (IN EFI_GUID *G, IN VOID *T)
{
  MARKSVC (16, 0);
  EFI_STATUS S = mOrigInstallCfg (G, T);
  TRACE ("[TR] InstallConfigurationTable %g -> %r\n", G, S);
  return S;
}

STATIC EFI_STATUS EFIAPI
TrConnect (IN EFI_HANDLE C, IN EFI_HANDLE *D, IN EFI_DEVICE_PATH_PROTOCOL *R, IN BOOLEAN Rec)
{
  MARKSVC (17, 0);
  TRACE ("[TR] ConnectController rec=%u ...\n", (UINT32)Rec);
  return mOrigConnect (C, D, R, Rec);
}

STATIC EFI_STATUS EFIAPI
TrLoadImage (IN BOOLEAN B, IN EFI_HANDLE P, IN EFI_DEVICE_PATH_PROTOCOL *Dp, IN VOID *Src, IN UINTN Sz, OUT EFI_HANDLE *H)
{
  MARKSVC (18, 0);
  CHAR16 *T = (Dp != NULL) ? ConvertDevicePathToText (Dp, FALSE, FALSE) : NULL;
  TRACE ("[TR] LoadImage %s ...\n", T != NULL ? T : L"?");
  if (T != NULL) {
    FreePool (T);
  }
  return mOrigLoadImage (B, P, Dp, Src, Sz, H);
}

STATIC EFI_STATUS EFIAPI
TrStartImage (IN EFI_HANDLE H, OUT UINTN *Sz, OUT CHAR16 **D)
{
  MARKSVC (19, 0);
  TRACE ("[TR] StartImage %p ...\n", H);
  return mOrigStartImage (H, Sz, D);
}

STATIC VOID
InstallTraces (VOID)
{
  mOrigAllocatePages = gBS->AllocatePages;  gBS->AllocatePages = TrAllocatePages;
  mOrigAllocatePool  = gBS->AllocatePool;   gBS->AllocatePool  = TrAllocatePool;
  mOrigFreePages     = gBS->FreePages;      gBS->FreePages     = TrFreePages;
  mOrigCreateEvent   = gBS->CreateEvent;    gBS->CreateEvent   = TrCreateEvent;
  mOrigCreateEventEx = gBS->CreateEventEx;  gBS->CreateEventEx = TrCreateEventEx;
  mOrigSetTimer      = gBS->SetTimer;       gBS->SetTimer      = TrSetTimer;
  mOrigSetWatchdog   = gBS->SetWatchdogTimer; gBS->SetWatchdogTimer = TrSetWatchdog;
  mOrigInstallCfg    = gBS->InstallConfigurationTable; gBS->InstallConfigurationTable = TrInstallCfg;
  mOrigConnect       = gBS->ConnectController; gBS->ConnectController = TrConnect;
  mOrigLoadImage     = gBS->LoadImage;      gBS->LoadImage     = TrLoadImage;
  mOrigStartImage    = gBS->StartImage;     gBS->StartImage    = TrStartImage;

  mOrigHandleProtocol     = gBS->HandleProtocol;      gBS->HandleProtocol     = TrHandleProtocol;
  mOrigLocateProtocol     = gBS->LocateProtocol;      gBS->LocateProtocol     = TrLocateProtocol;
  mOrigOpenProtocol       = gBS->OpenProtocol;        gBS->OpenProtocol       = TrOpenProtocol;
  mOrigLocateHandleBuffer = gBS->LocateHandleBuffer;  gBS->LocateHandleBuffer = TrLocateHandleBuffer;
  mOrigGetMemoryMap       = gBS->GetMemoryMap;        gBS->GetMemoryMap       = TrGetMemoryMap;
  mOrigStall              = gBS->Stall;               gBS->Stall              = TrStall;
  mOrigWaitForEvent       = gBS->WaitForEvent;        gBS->WaitForEvent       = TrWaitForEvent;
  mOrigCheckEvent         = gBS->CheckEvent;          gBS->CheckEvent         = TrCheckEvent;
  gBS->Hdr.CRC32 = 0;
  gBS->CalculateCrc32 (gBS, gBS->Hdr.HeaderSize, &gBS->Hdr.CRC32);

  mOrigGetVariable = gRT->GetVariable;  gRT->GetVariable = TrGetVariable;
  mOrigSetVariable = gRT->SetVariable;  gRT->SetVariable = TrSetVariable;
  gRT->Hdr.CRC32 = 0;
  gBS->CalculateCrc32 (gRT, gRT->Hdr.HeaderSize, &gRT->Hdr.CRC32);

  if (gST->ConOut != NULL) {
    mOrigOutputString = gST->ConOut->OutputString;  gST->ConOut->OutputString = TrOutputString;
  }
  if (gST->ConIn != NULL) {
    mOrigReadKey = gST->ConIn->ReadKeyStroke;       gST->ConIn->ReadKeyStroke = TrReadKey;
  }
  gST->Hdr.CRC32 = 0;
  gBS->CalculateCrc32 (gST, gST->Hdr.HeaderSize, &gST->Hdr.CRC32);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] service tracing installed\n"));
}

#include <Library/CacheMaintenanceLib.h>
#include <Guid/Acpi.h>
#include <Protocol/MemoryAttribute.h>

STATIC VOID
DumpConfigTables (VOID)
{
  UINTN Index;
  for (Index = 0; Index < gST->NumberOfTableEntries; Index++) {
    EFI_CONFIGURATION_TABLE *T = &gST->ConfigurationTable[Index];
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] cfgtbl[%lu] %g -> %p\n", (UINT64)Index, &T->VendorGuid, T->VendorTable));
    if (CompareGuid (&T->VendorGuid, &gEfiAcpi20TableGuid)) {
      UINT8  *Rsdp = (UINT8 *)T->VendorTable;
      UINT64 Xsdt  = *(UINT64 *)(Rsdp + 24);
      UINT32 Len   = *(UINT32 *)((UINT8 *)(UINTN)Xsdt + 4);
      UINTN  N     = (Len - 36) / 8;
      UINTN  K;
      DEBUG ((DEBUG_ERROR, "[MUCHAIN]   RSDP %c%c%c%c%c%c%c%c XSDT=0x%lx entries=%lu\n",
              Rsdp[0], Rsdp[1], Rsdp[2], Rsdp[3], Rsdp[4], Rsdp[5], Rsdp[6], Rsdp[7], Xsdt, (UINT64)N));
      DEBUG ((DEBUG_ERROR, "[MUCHAIN]   XSDT length=%u\n", Len));
      for (K = 0; K < N && K < 32; K++) {
        UINT64 Ptr = ((UINT64 *)((UINT8 *)(UINTN)Xsdt + 36))[K];
        UINT8  *Tab = (UINT8 *)(UINTN)Ptr;
        if (Ptr == 0) {
          DEBUG ((DEBUG_ERROR, "[MUCHAIN]   xsdt[%lu] = NULL\n", (UINT64)K));
          continue;
        }
        DEBUG ((DEBUG_ERROR, "[MUCHAIN]   xsdt[%lu] = 0x%lx %c%c%c%c len=%u\n", (UINT64)K, Ptr, Tab[0], Tab[1], Tab[2], Tab[3], *(UINT32 *)(Tab + 4)));
        if (Tab[0] == 'F' && Tab[1] == 'A' && Tab[2] == 'C' && Tab[3] == 'P') {
          UINT64 Dsdt = *(UINT64 *)(Tab + 140);
          UINT32 Dsdt32 = *(UINT32 *)(Tab + 40);
          DEBUG ((DEBUG_ERROR, "[MUCHAIN]   FADT: DSDT32=0x%x X_DSDT=0x%lx FACS=0x%x\n", Dsdt32, Dsdt, *(UINT32 *)(Tab + 36)));
          {
            UINT8  *Ds = (UINT8 *)(UINTN)Dsdt;
            UINT32 Dl  = *(UINT32 *)(Ds + 4);
            UINT32 q;
            BOOLEAN Has = FALSE;
            for (q = 36; q + 4 <= Dl; q++) {
              if (Ds[q] == 'D' && Ds[q + 1] == 'B' && Ds[q + 2] == 'G' && Ds[q + 3] == '0') { Has = TRUE; break; }
            }
            DEBUG ((DEBUG_ERROR, "[MUCHAIN]   DSDT len=%u has_DBG0=%u\n", Dl, (UINT32)Has));
          }
        }
      }
    }
  }
}

//
// \BRK.TXT on the volume MuChain was loaded from: whitespace separated hex
// RVAs inside bootmgfw.efi; each gets a BRK #n so Mu's exception handler dumps
// registers + stack when execution reaches it (breadcrumb / bisect tool).
//
STATIC VOID
PatchBreakpoints (IN EFI_HANDLE Image)
{
  EFI_LOADED_IMAGE_PROTOCOL        *Li = NULL;
  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL  *Fs = NULL;
  EFI_FILE_PROTOCOL                *Root = NULL, *File = NULL;
  EFI_MEMORY_ATTRIBUTE_PROTOCOL    *Ma = NULL;
  CHAR8                            Buf[257];
  UINTN                            Size = 256, I = 0, N = 0;

  if (mSelfVolume == NULL ||
      EFI_ERROR (gBS->HandleProtocol (Image, &gEfiLoadedImageProtocolGuid, (VOID **)&Li)) ||
      EFI_ERROR (gBS->HandleProtocol (mSelfVolume, &gEfiSimpleFileSystemProtocolGuid, (VOID **)&Fs)) ||
      EFI_ERROR (Fs->OpenVolume (Fs, &Root)) ||
      EFI_ERROR (Root->Open (Root, &File, L"\\BRK.TXT", EFI_FILE_MODE_READ, 0))) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] no BRK.TXT (no breakpoints)\n"));
    return;
  }
  if (EFI_ERROR (File->Read (File, &Size, Buf))) {
    return;
  }
  Buf[Size] = 0;
  File->Close (File);
  Root->Close (Root);
  gBS->LocateProtocol (&gEfiMemoryAttributeProtocolGuid, NULL, (VOID **)&Ma);

  while (I < Size) {
    UINT64 Rva = 0;
    BOOLEAN Got = FALSE;
    while (I < Size && Buf[I] <= ' ') {
      I++;
    }
    while (I < Size && ((Buf[I] >= '0' && Buf[I] <= '9') || (Buf[I] >= 'a' && Buf[I] <= 'f') || (Buf[I] >= 'A' && Buf[I] <= 'F'))) {
      CHAR8 C = Buf[I++];
      Rva = (Rva << 4) | (UINT64)(C <= '9' ? C - '0' : (C | 0x20) - 'a' + 10);
      Got = TRUE;
    }
    if (!Got) {
      break;
    }
    {
      UINT32 *P = (UINT32 *)((UINTN)Li->ImageBase + Rva);
      UINT32 Old = *P;
      EFI_STATUS S = EFI_SUCCESS;
      if (Ma != NULL) {
        S = Ma->ClearMemoryAttributes (Ma, ((UINT64)(UINTN)P) & ~0xFFFULL, 0x1000, EFI_MEMORY_RO);
      }
      N++;
      *P = 0xD4200000U | ((UINT32)N << 5);   // BRK #N
      WriteBackInvalidateDataCacheRange (P, 4);
      InvalidateInstructionCacheRange (P, 4);
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] BRK #%lu at image+0x%lx (0x%lx) old=0x%08x ClearRO=%r\n",
              (UINT64)N, Rva, (UINT64)(UINTN)P, Old, S));
    }
  }
}

#include <Protocol/HardwareInterrupt.h>
#include <Library/ArmLib.h>

STATIC UINT64   mBmBase = 0, mBmSize = 0;

STATIC UINT64 mProfN = 0;

STATIC VOID EFIAPI
ProfTick (IN EFI_EVENT Event, IN VOID *Context)
{
  UINT64 Elr, Spsr, Sp;
  __asm__ volatile ("mrs %0, elr_el1"  : "=r" (Elr));
  __asm__ volatile ("mrs %0, spsr_el1" : "=r" (Spsr));
  __asm__ volatile ("mov %0, sp"       : "=r" (Sp));
  mProfN++;
  if (mProfN > 600) {
    return;
  }
  if (Elr >= mBmBase && Elr < mBmBase + mBmSize) {
    DEBUG ((DEBUG_ERROR, "[PROF] #%lu elr=0x%lx (bootmgfw+0x%lx) spsr=0x%lx\n", mProfN, Elr, Elr - mBmBase, Spsr));
  } else {
    DEBUG ((DEBUG_ERROR, "[PROF] #%lu elr=0x%lx (other) spsr=0x%lx\n", mProfN, Elr, Spsr));
  }
}

STATIC VOID
StartProfiler (VOID)
{
  EFI_EVENT Ev = NULL;
  EFI_STATUS S = gBS->CreateEvent (EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, ProfTick, NULL, &Ev);
  if (!EFI_ERROR (S)) {
    S = gBS->SetTimer (Ev, TimerPeriodic, 2000000);   // 200 ms
  }
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] profiler (ELR_EL1 in timer notify): %r\n", S));
}
STATIC VOID
DumpDiskPaths (VOID)
{
  EFI_HANDLE *Handles = NULL;
  UINTN      Count = 0, Index;

  if (EFI_ERROR (gBS->LocateHandleBuffer (ByProtocol, &gEfiBlockIoProtocolGuid, NULL, &Count, &Handles))) {
    return;
  }
  for (Index = 0; Index < Count; Index++) {
    EFI_BLOCK_IO_PROTOCOL *B = NULL;
    if (EFI_ERROR (gBS->HandleProtocol (Handles[Index], &gEfiBlockIoProtocolGuid, (VOID **)&B)) || B == NULL || B->Media == NULL) {
      continue;
    }
    if (!B->Media->LogicalPartition) {
      CHAR16 *T = ConvertDevicePathToText (DevicePathFromHandle (Handles[Index]), FALSE, FALSE);
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] DISK handle=%p last=0x%lx bs=%u present=%u path=%s\n",
              Handles[Index], (UINT64)B->Media->LastBlock, B->Media->BlockSize, (UINT32)B->Media->MediaPresent,
              T != NULL ? T : L"?"));
      if (T != NULL) {
        FreePool (T);
      }
    }
  }
  FreePool (Handles);
}

STATIC VOID
ProbeWindowsPartition (VOID)
{
  EFI_HANDLE *Handles = NULL;
  UINTN      Count = 0, Index;

  if (EFI_ERROR (gBS->LocateHandleBuffer (ByProtocol, &gEfiBlockIoProtocolGuid, NULL, &Count, &Handles))) {
    return;
  }
  for (Index = 0; Index < Count; Index++) {
    EFI_BLOCK_IO_PROTOCOL *B = NULL;
    if (EFI_ERROR (gBS->HandleProtocol (Handles[Index], &gEfiBlockIoProtocolGuid, (VOID **)&B)) || B == NULL || B->Media == NULL) {
      continue;
    }
    if (B->Media->LogicalPartition && B->Media->LastBlock == 0x1FE4CB6ULL) {
      UINT8      *Buf = AllocatePool (B->Media->BlockSize);
      EFI_STATUS S    = EFI_OUT_OF_RESOURCES;
      CHAR16     *T   = ConvertDevicePathToText (DevicePathFromHandle (Handles[Index]), FALSE, FALSE);
      if (Buf != NULL) {
        S = B->ReadBlocks (B, B->Media->MediaId, 0, B->Media->BlockSize, Buf);
      }
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] windows part found: %s\n", T != NULL ? T : L"?"));
      DEBUG ((DEBUG_ERROR, "[MUCHAIN]   read LBA0: %r bs=%u oem=%c%c%c%c%c%c%c%c bps=%u spc=%u\n", S, B->Media->BlockSize,
              Buf[3], Buf[4], Buf[5], Buf[6], Buf[7], Buf[8], Buf[9], Buf[10], *(UINT16 *)(Buf + 11), Buf[13]));
      if (T != NULL) {
        FreePool (T);
      }
      FreePool (Buf);
    }
  }
  FreePool (Handles);
}


//
// Query Request UPIU through UTRL slot 31 (the firmware driver only uses slot 0).
// Opcode: 5 = READ_FLAG, 6 = SET_FLAG.   Returns the flag value in *Val.
//
STATIC EFI_STATUS
UfsQueryFlag (IN UINT64 Base, IN UINT8 Opcode, IN UINT8 Idn, OUT UINT8 *Val, OUT UINT8 *RespCode)
{
  EFI_PHYSICAL_ADDRESS         Ucd;
  UINT64                       Utrl;
  volatile UINT32              *Trd;
  volatile UINT8               *U;
  EFI_TPL                      Old;
  UINT32                       Spin;
  EFI_STATUS                   S = EFI_SUCCESS;
  CONST UINT32                 Slot = 31;

  *Val = 0xFF;
  *RespCode = 0xFF;
  Utrl = ((UINT64)*(volatile UINT32 *)(UINTN)(Base + 0x54) << 32) | *(volatile UINT32 *)(UINTN)(Base + 0x50);
  if (Utrl < 0x80000000ULL || Utrl >= 0x100000000ULL ||
      (*(volatile UINT32 *)(UINTN)(Base + 0x60) & 1) == 0 ||
      *(volatile UINT32 *)(UINTN)(Base + 0x58) != 0) {
    return EFI_NOT_READY;
  }
  if (mUfsUcd == 0) {
    if (mInEbs) {
      return EFI_NOT_READY;   // never allocate inside the EBS hook
    }
    mUfsUcd = 0xFFFFFFFFULL;
    S = gBS->AllocatePages (AllocateMaxAddress, EfiBootServicesData, 1, &mUfsUcd);
    if (EFI_ERROR (S)) {
      mUfsUcd = 0;
      return S;
    }
  }
  Ucd = mUfsUcd;
  ZeroMem ((VOID *)(UINTN)Ucd, 4096);
  U = (volatile UINT8 *)(UINTN)Ucd;
  U[0]  = 0x16;                                   // Query Request UPIU
  U[3]  = 0x5A;                                   // task tag
  U[5]  = (Opcode == 5) ? 0x01 : 0x81;            // standard read / write request
  U[12] = Opcode;
  U[13] = Idn;
  Trd = (volatile UINT32 *)(UINTN)(Utrl + Slot * 32);
  Trd[0] = 0x01000000;                            // same format as the firmware driver's slot 0 (Int=1, CT=0, DD=0)
  Trd[1] = 0;
  Trd[2] = 0x0F;                                  // OCS: invalid until the HC completes it
  Trd[3] = 0;
  Trd[4] = (UINT32)Ucd;
  Trd[5] = (UINT32)(Ucd >> 32);
  Trd[6] = 0x00080010;                            // response UPIU: offset 8 dwords (+0x20), length 16 dwords
  Trd[7] = 0x00180000;                            // PRDT offset 0x18 dwords, length 0
  WriteBackInvalidateDataCacheRange ((VOID *)(UINTN)Ucd, 4096);
  WriteBackInvalidateDataCacheRange ((VOID *)Trd, 32);

  Old = gBS->RaiseTPL (TPL_HIGH_LEVEL);
  *(volatile UINT32 *)(UINTN)(Base + 0x58) = (UINT32)(1U << Slot);
  for (Spin = 0; Spin < 1000000; Spin++) {
    if ((*(volatile UINT32 *)(UINTN)(Base + 0x58) & (1U << Slot)) == 0) {
      break;
    }
    gBS->Stall (1);
  }
  gBS->RestoreTPL (Old);
  if (Spin >= 1000000) {
    *(volatile UINT32 *)(UINTN)(Base + 0x5C) = ~(1U << Slot);   // UTRLCLR: abort our slot
    return EFI_TIMEOUT;
  }
  InvalidateDataCacheRange ((VOID *)(UINTN)Ucd, 4096);
  InvalidateDataCacheRange ((VOID *)Trd, 32);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSQ op=%u idn=%u: OCS=0x%x resp[0..3]=%02x %02x %02x %02x qresp=0x%02x flag=0x%02x (spins=%u)\n",
          Opcode, Idn, Trd[2] & 0xFF, U[0x20], U[0x21], U[0x22], U[0x23], U[0x26], U[0x20 + 23], Spin));
  *RespCode = U[0x26];
  *Val = U[0x20 + 23];
  return ((Trd[2] & 0xFF) == 0) ? EFI_SUCCESS : EFI_DEVICE_ERROR;
}

STATIC VOID
UfsHighDmaTest (IN UINT64 Base)
{
  STATIC CONST UINT64  Max[] = { 0x880100000ULL, 0x8C0100000ULL, 0xAFFFEB000ULL };   // inside the three high DRAM regions (AllocateAddress)
  UINTN                K;

  for (K = 0; K < ARRAY_SIZE (Max); K++) {
    EFI_PHYSICAL_ADDRESS  High = Max[K];
    EFI_PHYSICAL_ADDRESS  Save = mUfsUcd;
    EFI_STATUS            S, Q;
    UINT8                 V = 0xFF, R = 0xFF;

    S = gBS->AllocatePages (AllocateAddress, EfiBootServicesData, 1, &High);
    if (EFI_ERROR (S) || High < 0x100000000ULL) {
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] HIGHDMA max=0x%lx: no page above 4GB (%r, got 0x%lx)\n", Max[K], S, (UINT64)High));
      if (!EFI_ERROR (S)) { gBS->FreePages (High, 1); }
      continue;
    }
    mUfsUcd = High;
    Q = UfsQueryFlag (Base, 5, 3, &V, &R);
    mUfsUcd = Save;
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] HIGHDMA ucd=0x%lx: READ_FLAG %r flag=%u qresp=0x%x\n", (UINT64)High, Q, V, R));
    if (Q == EFI_TIMEOUT) {
      // do not touch the controller any more after a DMA timeout; leave the page allocated
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] HIGHDMA: timeout -> stop testing\n"));
      return;
    }
    gBS->FreePages (High, 1);
  }
}

STATIC VOID
UfsProbeOne (IN UINT64 Base, IN UINTN Len, IN BOOLEAN Regs)
{
  EFI_GCD_MEMORY_SPACE_DESCRIPTOR  D;
  EFI_STATUS                       S;

  S = gDS->GetMemorySpaceDescriptor (Base, &D);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSPROBE gcd 0x%lx: %r type=%d attr=0x%lx base=0x%lx len=0x%lx\n",
          Base, S, S == EFI_SUCCESS ? (INT32)D.GcdMemoryType : -1, S == EFI_SUCCESS ? D.Attributes : 0,
          S == EFI_SUCCESS ? D.BaseAddress : 0, S == EFI_SUCCESS ? D.Length : 0));
  if (EFI_ERROR (S) || D.GcdMemoryType != EfiGcdMemoryTypeMemoryMappedIo || !Regs) {
    return;
  }
  {
    // standard UFSHCI register file (read-only)
    STATIC CONST struct { UINT32 Off; CONST CHAR8 *Name; } Reg[] = {
      { 0x00, "CAP" }, { 0x08, "VER" }, { 0x10, "HCDDID" }, { 0x14, "HCPMID" }, { 0x20, "IS" }, { 0x24, "IE" },
      { 0x30, "HCS" }, { 0x34, "HCE" }, { 0x38, "UECPA" }, { 0x3C, "UECDL" }, { 0x40, "UECN" }, { 0x44, "UECT" },
      { 0x48, "UECDME" }, { 0x4C, "UTRIACR" }, { 0x50, "UTRLBA" }, { 0x54, "UTRLBAU" }, { 0x58, "UTRLDBR" },
      { 0x5C, "UTRLCLR" }, { 0x60, "UTRLRSR" }, { 0x64, "UTRLCNR" }, { 0x70, "UTMRLBA" }, { 0x74, "UTMRLBAU" },
      { 0x78, "UTMRLDBR" }, { 0x80, "UTMRLRSR" }, { 0x90, "UICCMD" }, { 0x94, "UCMDARG1" }, { 0x98, "UCMDARG2" },
      { 0x9C, "UCMDARG3" },
    };
    UINTN K;
    for (K = 0; K < ARRAY_SIZE (Reg); K++) {
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSHC %-8a [0x%02x] = 0x%08x\n", Reg[K].Name, Reg[K].Off,
              *(volatile UINT32 *)(UINTN)(Base + Reg[K].Off)));
    }
    {
      UINT64 Utrl = ((UINT64)*(volatile UINT32 *)(UINTN)(Base + 0x54) << 32) | *(volatile UINT32 *)(UINTN)(Base + 0x50);
      UINTN  Slot, W;
      if (Utrl >= 0x80000000ULL && Utrl < 0x100000000ULL) {
        for (Slot = 0; Slot < 32; Slot++) {
          volatile UINT32 *D = (volatile UINT32 *)(UINTN)(Utrl + Slot * 32);
          UINT32          Any = 0;
          for (W = 0; W < 8; W++) { Any |= D[W]; }
          if (Any != 0) {
            UINT64 Ucd = ((UINT64)D[5] << 32) | D[4];
            DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSTRL slot %lu: %08x %08x %08x %08x ucd=0x%lx %08x %08x\n", (UINT64)Slot,
                    D[0], D[1], D[2], D[3], Ucd, D[6], D[7]));
            if (Slot == 0 && Ucd >= 0x80000000ULL && Ucd < 0x100000000ULL) {
              volatile UINT32 *U = (volatile UINT32 *)(UINTN)Ucd;
              for (W = 0; W < 24; W += 4) {
                DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSUCD0 +0x%02x: %08x %08x %08x %08x\n", (UINT32)(W * 4), U[W], U[W + 1], U[W + 2], U[W + 3]));
              }
            }
          }
        }
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSTRL dump done (list at 0x%lx)\n", Utrl));
      }
      {
        UINT8 V, R;
        EFI_STATUS Q;
        // READ_FLAG only (no device state change): fDeviceInit(1), fPermanentWPEn(2), fPowerOnWPEn(3)
        Q = UfsQueryFlag (Base, 5, 1, &V, &R);
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSQ fDeviceInit    : %r flag=%u qresp=0x%x\n", Q, V, R));
        Q = UfsQueryFlag (Base, 5, 2, &V, &R);
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSQ fPermanentWPEn : %r flag=%u qresp=0x%x\n", Q, V, R));
        Q = UfsQueryFlag (Base, 5, 3, &V, &R);
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSQ fPowerOnWPEn   : %r flag=%u qresp=0x%x\n", Q, V, R));
        if (mNoBoot) {
          UfsHighDmaTest (Base);   // diagnostics only in safe (NOBOOT) mode
        }
      }
    }
  }
}

STATIC EFI_STATUS
WriteTestFile (IN CONST CHAR16 *Name, IN CONST CHAR8 *Text)
{
  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *Fs = NULL;
  EFI_FILE_PROTOCOL               *Root = NULL, *File = NULL;
  EFI_STATUS                      S, S2 = EFI_SUCCESS, S3;
  UINTN                           Len = AsciiStrLen (Text);

  if (mSelfVolume == NULL ||
      EFI_ERROR (gBS->HandleProtocol (mSelfVolume, &gEfiSimpleFileSystemProtocolGuid, (VOID **)&Fs)) ||
      EFI_ERROR (Fs->OpenVolume (Fs, &Root))) {
    return EFI_NOT_FOUND;
  }
  S = Root->Open (Root, &File, (CHAR16 *)Name, EFI_FILE_MODE_READ | EFI_FILE_MODE_WRITE | EFI_FILE_MODE_CREATE, 0);
  if (!EFI_ERROR (S)) {
    S  = File->Write (File, &Len, (VOID *)Text);
    S2 = File->Flush (File);
    File->Close (File);
  }
  S3 = Root->Flush (Root);
  Root->Close (Root);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] WPTEST write %s: write=%r flush=%r volflush=%r\n", Name, S, S2, S3));
  if (EFI_ERROR (S)) { return S; }
  if (EFI_ERROR (S2)) { return S2; }
  return S3;
}

STATIC VOID
UfsWpTest (IN UINT64 Base)
{
  UINT8      V, R;
  EFI_STATUS Q;

  DEBUG ((DEBUG_ERROR, "[MUCHAIN] WPTEST begin\n"));
  Q = WriteTestFile (L"\\WPPRE.TXT", "before set_flag\n");
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] WPTEST pre-write result: %r (expect Success)\n", Q));
  if (EFI_ERROR (Q)) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] WPTEST abort: cannot even write before the flag\n"));
    return;
  }
  Q = UfsQueryFlag (Base, 6, 3, &V, &R);       // SET_FLAG fPowerOnWPEn
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] WPTEST SET_FLAG fPowerOnWPEn: %r flag=%u qresp=0x%x\n", Q, V, R));
  Q = UfsQueryFlag (Base, 5, 3, &V, &R);       // READ_FLAG
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] WPTEST READ_FLAG fPowerOnWPEn: %r flag=%u qresp=0x%x (expect flag=1)\n", Q, V, R));
  Q = WriteTestFile (L"\\WPPOST.TXT", "after set_flag\n");
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] WPTEST post-write result: %r (expect an error if LUN4 is protected)\n", Q));
}

STATIC BOOLEAN SelfFileExists (IN CONST CHAR16 *Name);
STATIC BOOLEAN SelfDeleteFile (IN CONST CHAR16 *Name);
STATIC INTN    SelfFirstByte (IN CONST CHAR16 *Name);

STATIC VOID
TsensProbe (VOID)
{
  STATIC CONST UINT64  Base[3] = { 0xC228000ULL, 0xC229000ULL, 0xC22A000ULL };
  UINTN                C, N;

  for (C = 0; C < 3; C++) {
    EFI_GCD_MEMORY_SPACE_DESCRIPTOR  D;
    EFI_STATUS                       S = gDS->GetMemorySpaceDescriptor (Base[C], &D);
    if (EFI_ERROR (S) || D.GcdMemoryType != EfiGcdMemoryTypeMemoryMappedIo) {
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] TSENS%u 0x%lx: not mapped as MMIO (%r type=%d)\n", (UINT32)C, Base[C], S, S == EFI_SUCCESS ? (INT32)D.GcdMemoryType : -1));
      continue;
    }
    for (N = 0; N < 16; N++) {
      UINT32 V = *(volatile UINT32 *)(UINTN)(Base[C] + 0xA0 + 4 * N);
      INT32  T = (INT32)(V & 0xFFF);
      if (T & 0x800) {
        T -= 0x1000;
      }
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] TSENS%u sensor %2u: raw=0x%08x temp=%d.%u C valid=%u\n", (UINT32)C, (UINT32)N, V, T / 10, (UINT32)((T < 0 ? -T : T) % 10), (V >> 21) & 1));
    }
  }
}

#define SPMI_CORE   0x0C400000ULL
#define SPMI_CNFG   0x0C42D000ULL
#define SPMI_OBSRVR 0x0C440000ULL

STATIC UINT16  mSpmiApid[4096];     // ppid -> apid+1 (0 = unknown / not owned by EE0)

STATIC BOOLEAN
SpmiReadBytes (IN UINT32 Sid, IN UINT32 Addr16, IN UINT32 Len, OUT UINT8 *Out)
{
  UINT32  Ppid = (Sid << 8) | (Addr16 >> 8);
  UINT32  Apid = mSpmiApid[Ppid & 0xFFF];
  UINT64  Off;
  UINT32  Cmd, I, St = 0;

  if (Apid == 0 || Len < 1 || Len > 8) {
    return FALSE;
  }
  Apid -= 1;
  Off = SPMI_OBSRVR + 0x20ULL * Apid;          // ee = 0
  Cmd = (1U << 27) | ((Addr16 & 0xFF) << 4) | (Len - 1);   // EXT_READL
  *(volatile UINT32 *)(UINTN)(Off + 0x00) = Cmd;
  for (I = 0; I < 1000; I++) {
    St = *(volatile UINT32 *)(UINTN)(Off + 0x08);
    if (St & 1) {
      break;
    }
    gBS->Stall (1);
  }
  if (!(St & 1) || (St & 0xE)) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] SPMI read sid=%u addr=0x%x failed status=0x%x\n", Sid, Addr16, St));
    return FALSE;
  }
  {
    UINT32 D0 = *(volatile UINT32 *)(UINTN)(Off + 0x18);
    UINT32 D1 = *(volatile UINT32 *)(UINTN)(Off + 0x1C);
    for (I = 0; I < Len; I++) {
      Out[I] = (UINT8)((I < 4 ? D0 >> (8 * I) : D1 >> (8 * (I - 4))) & 0xFF);
    }
  }
  return TRUE;
}

STATIC VOID
SpmiProbe (VOID)
{
  EFI_GCD_MEMORY_SPACE_DESCRIPTOR  D;
  UINT32                           Ver, Apid, Owned = 0, Total = 0;
  UINT8                            B[8];

  if (EFI_ERROR (gDS->GetMemorySpaceDescriptor (SPMI_CORE, &D)) || D.GcdMemoryType != EfiGcdMemoryTypeMemoryMappedIo ||
      EFI_ERROR (gDS->GetMemorySpaceDescriptor (SPMI_OBSRVR, &D)) || D.GcdMemoryType != EfiGcdMemoryTypeMemoryMappedIo) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] SPMI: arbiter regions not mapped as MMIO\n"));
    return;
  }
  Ver = *(volatile UINT32 *)(UINTN)(SPMI_CORE + 0);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] SPMI arbiter version 0x%08x  features0 0x%08x\n", Ver, *(volatile UINT32 *)(UINTN)(SPMI_CORE + 4)));
  if ((Ver & 0xF0000000U) != 0x70000000U) {
    return;
  }
  ZeroMem (mSpmiApid, sizeof (mSpmiApid));
  for (Apid = 0; Apid < 1024; Apid++) {
    UINT32 V = *(volatile UINT32 *)(UINTN)(SPMI_CORE + 0x2000 + 4ULL * Apid);
    UINT32 Ppid = (V >> 8) & 0xFFF;
    UINT32 Owner = *(volatile UINT32 *)(UINTN)(SPMI_CNFG + 4ULL * Apid) & 7;
    if (Ppid == 0 && V == 0) {
      continue;
    }
    Total++;
    if (Owner == 0 && mSpmiApid[Ppid] == 0) {
      mSpmiApid[Ppid] = (UINT16)(Apid + 1);
      Owned++;
    }
  }
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] SPMI apids mapped=%u, readable by EE0=%u\n", Total, Owned));
  {
    UINT32  Ppid, Cnt = 0;
    for (Ppid = 0; Ppid < 4096 && Cnt < 400; Ppid++) {
      if (mSpmiApid[Ppid] != 0) {
        UINT8 Type = 0xFF, Sub = 0xFF;
        UINT8 T[2];
        if (SpmiReadBytes (Ppid >> 8, (Ppid & 0xFF) << 8 | 0x04, 2, T)) {
          Type = T[0];
          Sub  = T[1];
        }
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] SPMI periph sid=%u base=0x%04x apid=%u type=0x%02x subtype=0x%02x\n", Ppid >> 8, (Ppid & 0xFF) << 8, mSpmiApid[Ppid] - 1, Type, Sub));
        Cnt++;
      }
    }
  }
  // PMK8550 RTC (sid 0): ctrl at 0x6146, seconds counter at 0x6148 (4 bytes, little endian)
  if (SpmiReadBytes (0, 0x6146, 1, B)) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] SPMI RTC ctrl = 0x%02x\n", B[0]));
  }
  if (SpmiReadBytes (0, 0x6148, 4, B)) {
    UINT32 Secs = B[0] | ((UINT32)B[1] << 8) | ((UINT32)B[2] << 16) | ((UINT32)B[3] << 24);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] SPMI RTC seconds = %u (0x%08x)\n", Secs, Secs));
  }
}

STATIC VOID
CmdDbProbe (VOID)
{
  CONST UINT8  *H = (CONST UINT8 *)(UINTN)0x81C60000ULL;
  UINT32       I, J, Total = 0;

  DEBUG ((DEBUG_ERROR, "[MUCHAIN] CMDDB hdr: version=0x%x magic=%02x %02x %02x %02x\n", *(CONST UINT32 *)H, H[4], H[5], H[6], H[7]));
  if (H[4] != 0xdb || H[5] != 0x30 || H[6] != 0x03 || H[7] != 0x0c) {
    return;
  }
  for (I = 0; I < 8; I++) {
    CONST UINT8  *R = H + 8 + 16 * I;
    UINT16       SlvId = *(CONST UINT16 *)(R + 0), HdrOff = *(CONST UINT16 *)(R + 2), Cnt = *(CONST UINT16 *)(R + 6);
    CONST UINT8  *E;

    if (SlvId == 0) {
      break;
    }
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] CMDDB slave %u: entries=%u (hdr off 0x%x)\n", SlvId, Cnt, HdrOff));
    E = H + 144 + HdrOff;
    for (J = 0; J < Cnt; J++, E += 24) {
      CHAR8  Name[9];
      UINT32 K;
      for (K = 0; K < 8; K++) {
        Name[K] = (E[K] >= 0x20 && E[K] < 0x7F) ? (CHAR8)E[K] : (E[K] == 0 ? 0 : '?');
      }
      Name[8] = 0;
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] CMDDB s%u %-8a addr=0x%05x len=%u\n", SlvId, Name, *(CONST UINT32 *)(E + 16), *(CONST UINT16 *)(E + 20)));
      Total++;
    }
  }
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] CMDDB total entries=%u\n", Total));
}

#define RSC_BASE         0x17A20000ULL
#define RSC_TCS_BASE     (RSC_BASE + 0xD00ULL)
#define RSC_R32(o)       (*(volatile UINT32 *)(UINTN)(RSC_BASE + (o)))
#define RSC_W32(o, v)    (*(volatile UINT32 *)(UINTN)(RSC_BASE + (o)) = (UINT32)(v))
#define IRQ_R32(o)       (*(volatile UINT32 *)(UINTN)(RSC_TCS_BASE + (o)))
#define IRQ_W32(o, v)    (*(volatile UINT32 *)(UINTN)(RSC_TCS_BASE + (o)) = (UINT32)(v))
#define TCS_REG(id, r)   (RSC_TCS_BASE + 672ULL * (id) + (r))
#define TCS_R32(id, r)   (*(volatile UINT32 *)(UINTN)TCS_REG (id, r))
#define TCS_W32(id, r, v) (*(volatile UINT32 *)(UINTN)TCS_REG (id, r) = (UINT32)(v))
#define TCS_CMD_REG(id, cmd, r) (TCS_REG (id, r) + 24ULL * (cmd))
#define V3_WAIT   0x20
#define V3_CTRL   0x24
#define V3_STATUS 0x28
#define V3_CMDEN  0x2C
#define V3_MSGID  0x34
#define V3_ADDR   0x38
#define V3_DATA   0x3C
#define V3_CMDST  0x40
#define AMC_ENABLE   (1U << 16)
#define AMC_TRIGGER  (1U << 24)

STATIC UINT32
CmdDbAddr (IN CONST CHAR8 *Name)
{
  CONST UINT8  *H = (CONST UINT8 *)(UINTN)0x81C60000ULL;
  UINT32       I, J, K;

  if (H[4] != 0xdb || H[5] != 0x30 || H[6] != 0x03 || H[7] != 0x0c) {
    return 0;
  }
  for (I = 0; I < 8; I++) {
    CONST UINT8  *R = H + 8 + 16 * I;
    UINT16       SlvId = *(CONST UINT16 *)(R + 0), HdrOff = *(CONST UINT16 *)(R + 2), Cnt = *(CONST UINT16 *)(R + 6);
    CONST UINT8  *E;

    if (SlvId == 0) {
      break;
    }
    E = H + 144 + HdrOff;
    for (J = 0; J < Cnt; J++, E += 24) {
      BOOLEAN M = TRUE;
      for (K = 0; K < 8; K++) {
        CHAR8 Ch = (K < AsciiStrLen (Name)) ? Name[K] : 0;
        if (E[K] != (UINT8)Ch) {
          M = FALSE;
          break;
        }
      }
      if (M) {
        return *(CONST UINT32 *)(E + 16);
      }
    }
  }
  return 0;
}

STATIC VOID
TcsSetTrigger (IN UINT32 Id, IN BOOLEAN Enable)
{
  UINT32 En = TCS_R32 (Id, V3_CTRL);

  if (Enable) {
    En &= ~AMC_TRIGGER;  TCS_W32 (Id, V3_CTRL, En);  (VOID)TCS_R32 (Id, V3_CTRL);
    En &= ~AMC_ENABLE;   TCS_W32 (Id, V3_CTRL, En);  (VOID)TCS_R32 (Id, V3_CTRL);
    En |= AMC_ENABLE;    TCS_W32 (Id, V3_CTRL, En);  (VOID)TCS_R32 (Id, V3_CTRL);
    En |= AMC_TRIGGER;   TCS_W32 (Id, V3_CTRL, En);  // go
  } else {
    En &= ~AMC_TRIGGER;  TCS_W32 (Id, V3_CTRL, En);  (VOID)TCS_R32 (Id, V3_CTRL);
    En &= ~AMC_ENABLE;   TCS_W32 (Id, V3_CTRL, En);  (VOID)TCS_R32 (Id, V3_CTRL);
  }
}

// one ACTIVE write {Addr, Data} using TCS 0 and waiting for completion; returns TRUE if the RSC reported completion
STATIC BOOLEAN
RpmhWrite (IN UINT32 Addr, IN UINT32 Data)
{
  CONST UINT32  Id = 0;
  UINT32        I, St = 0;
  UINT32        SvCmdEn, SvMsg[4], SvAddr[4], SvData[4];

  // Save TCS0 as Mu's own RpmhDxe left it, and put it back afterwards (ENABLE|TRIGGER stay set after a send = the state RpmhDxe expects;
  // leaving them cleared stalled its next request, which hung Mu's USB init on 2026-10-15).
  SvCmdEn = TCS_R32 (Id, V3_CMDEN);
  for (I = 0; I < 4; I++) {
    SvMsg[I]  = *(volatile UINT32 *)(UINTN)TCS_CMD_REG (Id, I, V3_MSGID);
    SvAddr[I] = *(volatile UINT32 *)(UINTN)TCS_CMD_REG (Id, I, V3_ADDR);
    SvData[I] = *(volatile UINT32 *)(UINTN)TCS_CMD_REG (Id, I, V3_DATA);
  }
  IRQ_W32 (0x08, 1U << Id);                                 // IRQ_CLEAR
  TCS_W32 (Id, V3_CMDEN, 0);
  TCS_W32 (Id, V3_MSGID, 8 | 0x100 | 0x10000);              // len=8, resp_req (wait), write
  TCS_W32 (Id, V3_ADDR, Addr);
  TCS_W32 (Id, V3_DATA, Data);
  TCS_W32 (Id, V3_CMDEN, 1);
  TcsSetTrigger (Id, TRUE);
  for (I = 0; I < 200000; I++) {                            // 200 ms
    St = IRQ_R32 (0x04);                                    // IRQ_STATUS
    if (St & (1U << Id)) {
      break;
    }
    gBS->Stall (1);
  }
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] RPMH write addr=0x%05x data=0x%x: irq_status=0x%x cmd_status=0x%x ctrl=0x%x (%u us)\n",
          Addr, Data, St, TCS_R32 (Id, V3_CMDST), TCS_R32 (Id, V3_CTRL), I));
  // keep CTRL = ENABLE|TRIGGER as the send left it (that is how RpmhDxe leaves it), restore the command enable mask and the first four commands
  TCS_W32 (Id, V3_CMDEN, SvCmdEn);
  for (I = 0; I < 4; I++) {
    *(volatile UINT32 *)(UINTN)TCS_CMD_REG (Id, I, V3_MSGID) = SvMsg[I];
    *(volatile UINT32 *)(UINTN)TCS_CMD_REG (Id, I, V3_ADDR)  = SvAddr[I];
    *(volatile UINT32 *)(UINTN)TCS_CMD_REG (Id, I, V3_DATA)  = SvData[I];
  }
  IRQ_W32 (0x08, 1U << Id);
  return (St & (1U << Id)) != 0;
}

STATIC VOID
RpmhProbe (VOID)
{
  EFI_GCD_MEMORY_SPACE_DESCRIPTOR  D;
  UINT32                           Ld, I, Cfg;

  if (EFI_ERROR (gDS->GetMemorySpaceDescriptor (RSC_BASE, &D)) || D.GcdMemoryType != EfiGcdMemoryTypeMemoryMappedIo) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] RPMH: RSC DRV2 not mapped as MMIO\n"));
    return;
  }
  Cfg = RSC_R32 (0x0C);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] RPMH DRV2: id=0x%08x solver=0x%x prnt_chld=0x%08x irq_en=0x%x irq_st=0x%x\n", RSC_R32 (0x0), RSC_R32 (0x04), Cfg, IRQ_R32 (0x00), IRQ_R32 (0x04)));
  for (I = 0; I < 8; I++) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] RPMH TCS%u ctrl=0x%08x status=0x%08x cmd_enable=0x%08x\n", I, TCS_R32 (I, V3_CTRL), TCS_R32 (I, V3_STATUS), TCS_R32 (I, V3_CMDEN)));
  }
  Ld = CmdDbAddr ("ldob15");
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] RPMH cmd-db ldob15 addr=0x%x\n", Ld));
  if (Ld != 0) {
    // VRM enable register = base + 0x4
    BOOLEAN Ok = RpmhWrite (Ld + 0x4, 1);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] RPMH ACTIVE write completed: %a\n", Ok ? "YES" : "NO"));
  }
}
STATIC CONST UINT16 mPciePhySeq[][3] = {
  { 0x240, 0x3, 0 }, { 0xC0, 0x1, 0 }, { 0xCC, 0x62, 0 }, { 0xD0, 0x2, 0 }, { 0x60, 0xF8, 0 },
  { 0x64, 0x1, 0 }, { 0x0, 0x93, 0 }, { 0x4, 0x1, 0 }, { 0xE0, 0x90, 0 }, { 0xE4, 0x82, 0 },
  { 0xF4, 0x7, 0 }, { 0x70, 0x2, 0 }, { 0x10, 0x2, 0 }, { 0x74, 0x16, 0 }, { 0x14, 0x16, 0 },
  { 0x78, 0x36, 0 }, { 0x18, 0x36, 0 }, { 0x110, 0x8, 0 }, { 0xBC, 0xA, 0 }, { 0x120, 0x42, 0 },
  { 0x80, 0x4, 0 }, { 0x84, 0xD, 0 }, { 0x20, 0xA, 0 }, { 0x24, 0x1A, 0 }, { 0x88, 0x41, 0 },
  { 0x28, 0x34, 0 }, { 0x90, 0xAB, 0 }, { 0x94, 0xAA, 0 }, { 0x98, 0x1, 0 }, { 0x30, 0x55, 0 },
  { 0x34, 0x55, 0 }, { 0x38, 0x1, 0 }, { 0x140, 0x14, 0 }, { 0x164, 0x34, 0 }, { 0x3C, 0x1, 0 },
  { 0x1C, 0x4, 0 }, { 0x174, 0x16, 0 }, { 0x1BC, 0xF, 0 }, { 0x170, 0xA0, 0 }, { 0x11A4, 0x38, 0 },
  { 0x10DC, 0x11, 0 }, { 0x1160, 0xBF, 0 }, { 0x1164, 0xBF, 0 }, { 0x1168, 0xB7, 0 }, { 0x116C, 0xEA, 0 },
  { 0x115C, 0x3F, 0 }, { 0x1174, 0x5C, 0 }, { 0x1178, 0x9C, 0 }, { 0x117C, 0x1A, 0 }, { 0x1180, 0x89, 0 },
  { 0x1170, 0xDC, 0 }, { 0x1188, 0x94, 0 }, { 0x118C, 0x5B, 0 }, { 0x1190, 0x1A, 0 }, { 0x1194, 0x89, 0 },
  { 0x10CC, 0x0, 0 }, { 0x1008, 0x9, 0 }, { 0x1014, 0x5, 0 }, { 0x104C, 0x8, 0 }, { 0x1050, 0x8, 0 },
  { 0x10D8, 0xF, 0 }, { 0x1118, 0x1C, 0 }, { 0x10F8, 0x7, 0 }, { 0x11F8, 0x8, 0 }, { 0x1600, 0x0, 0 },
  { 0xE84, 0x15, 0 }, { 0xE90, 0x3F, 0 }, { 0xEE4, 0x2, 0 }, { 0xE40, 0x9, 0 }, { 0xE3C, 0x15, 0 },
  { 0x19A4, 0x38, 0 }, { 0x18DC, 0x11, 0 }, { 0x1960, 0xBF, 0 }, { 0x1964, 0xBF, 0 }, { 0x1968, 0xB7, 0 },
  { 0x196C, 0xEA, 0 }, { 0x195C, 0x3F, 0 }, { 0x1974, 0x5C, 0 }, { 0x1978, 0x9C, 0 }, { 0x197C, 0x1A, 0 },
  { 0x1980, 0x89, 0 }, { 0x1970, 0xDC, 0 }, { 0x1988, 0x94, 0 }, { 0x198C, 0x5B, 0 }, { 0x1990, 0x1A, 0 },
  { 0x1994, 0x89, 0 }, { 0x18CC, 0x0, 0 }, { 0x1808, 0x9, 0 }, { 0x1814, 0x5, 0 }, { 0x184C, 0x8, 0 },
  { 0x1850, 0x8, 0 }, { 0x18D8, 0xF, 0 }, { 0x1918, 0x1C, 0 }, { 0x18F8, 0x7, 0 }, { 0x19F8, 0x8, 0 },
  { 0x1684, 0x15, 0 }, { 0x1690, 0x3F, 0 }, { 0x16E4, 0x2, 0 }, { 0x1640, 0x9, 0 }, { 0x163C, 0x15, 0 },
  { 0x2DC, 0x5, 0 }, { 0x388, 0x77, 0 }, { 0x398, 0xB, 0 }, { 0x6A4, 0x1E, 0 }, { 0x6F4, 0x27, 0 },
  { 0x3E0, 0xF, 0 }, { 0x60C, 0x1D, 0 }, { 0x614, 0x7, 0 }, { 0x620, 0xC1, 0 }, { 0x694, 0x0, 0 },
  { 0x3D0, 0x8C, 0 }, { 0x368, 0x17, 0 }, { 0x200, 0x0, 0 }, { 0x244, 0x3, 0 },
};


#define MMR(a)       (*(volatile UINT32 *)(UINTN)(a))
#define MMW(a, v)    (*(volatile UINT32 *)(UINTN)(a) = (UINT32)(v))
STATIC BOOLEAN  mPcQuiet = FALSE;   // set during the WLAN_EN -> PERST window: the on-screen log costs ms per line and Android needs ~19 ms
#define PL(...)      do { if (!mPcQuiet) { DEBUG ((DEBUG_ERROR, "[MUCHAIN] PCIE " __VA_ARGS__)); } } while (0)
#define GCC_B        0x100000ULL
#define PARF_B       0x1C00000ULL
#define PHY_B        0x1C06000ULL
#define DBI_B        0x60000000ULL
#define ATU_B        0x60001000ULL
#define CFG_B        0x60100000ULL
#define TLMM_B       0x0F100000ULL      // mainline sm8650 tlmm @f100000 (downstream node 'pinctrl@f000000' spans the whole TLMM space)
#define TCSR_CLKREF  0x01FF1100ULL      // tcsrcc base 0x1fc0000 + 0x31100 (mainline sm8650)

STATIC UINT64
PcNowUs (VOID)
{
  UINT64  Cnt;

  __asm__ volatile ("mrs %0, cntvct_el0" : "=r" (Cnt));
  return Cnt / 19;                                           // 19.2 MHz counter -> ~us
}

STATIC VOID
PcDelayMs (UINTN Ms)
{
  while (Ms--) {
    gBS->Stall (1000);
  }
}

STATIC VOID
PcEnsureMmio (IN UINT64 Base, IN UINT64 Len, IN CONST CHAR8 *Name)
{
  EFI_GCD_MEMORY_SPACE_DESCRIPTOR  D;
  EFI_STATUS                       S = gDS->GetMemorySpaceDescriptor (Base, &D);

  if (EFI_ERROR (S)) {
    PL ("map %a 0x%lx: GetDescriptor %r\n", Name, Base, S);
    return;
  }
  if (D.GcdMemoryType == EfiGcdMemoryTypeMemoryMappedIo) {
    PL ("map %a 0x%lx: already MMIO (attr 0x%lx)\n", Name, Base, D.Attributes);
    return;
  }
  if (D.GcdMemoryType != EfiGcdMemoryTypeNonExistent) {
    PL ("map %a 0x%lx: unexpected GCD type %d\n", Name, Base, (INT32)D.GcdMemoryType);
    return;
  }
  if (Base + Len > D.BaseAddress + D.Length) {
    Len = D.BaseAddress + D.Length - Base;
  }
  S = gDS->AddMemorySpace (EfiGcdMemoryTypeMemoryMappedIo, Base, Len, EFI_MEMORY_UC | EFI_MEMORY_XP);
  PL ("map %a 0x%lx+0x%lx: Add %r", Name, Base, Len, S);
  S = gDS->SetMemorySpaceAttributes (Base, Len, EFI_MEMORY_UC | EFI_MEMORY_XP);
  DEBUG ((DEBUG_ERROR, " SetAttr %r\n", S));
}

// Cap the CPU clusters through the EPSS cpufreq-hw performance-state registers (+0x320 of each frequency domain; the same register Linux's qcom-cpufreq-hw writes).
// Windows on this phone has no working processor power manager (FxPPM fails to load), so left alone every cluster stays at the boot-time maximum and an idle-but-busy Windows
// sits at 85-94 C.  Measured 2026-10-27: capped to ~1.3-1.5 GHz it idles at 48-55 C.  dbgcap.sys keeps the cap once Windows is up; this makes it hold from MuChain's start.
// Domain order = Android's: dom0 cpu0-1, dom1 cpu5-6, dom2 cpu7, dom3 cpu2-4.  The frequency LUT is at +0x100 (low 8 bits x 19.2 MHz); nothing is written unless the LUT looks sane.
STATIC VOID
EpssCapApply (IN BOOLEAN FirstCall)
{
  STATIC CONST UINT32  Base[4]   = { 0x17D91000U, 0x17D92000U, 0x17D93000U, 0x17D94000U };
  STATIC CONST UINT32  Target[4] = { 1344, 1498, 1478, 1498 };   // MHz
  UINT32               Idx[4];
  UINTN                D, I;

  if (FirstCall) {
    mEpssCapOff = SelfFileExists (L"\\NOCAP.TXT");
    if (mEpssCapOff) {
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] EPSS cap: NOCAP.TXT present, frequencies left alone\n"));
    } else {
      PcEnsureMmio (0x17D91000ULL, 0x4000, "EPSS");
    }
  }
  if (mEpssCapOff) {
    return;
  }
  for (D = 0; D < 4; D++) {
    UINT32  Best = 0, Bd = 0xFFFFFFFFU, N = 0;

    for (I = 0; I < 40; I++) {
      UINT32  Lv = *(volatile UINT32 *)(UINTN)(Base[D] + 0x100 + 4 * I) & 0xFF;
      UINT32  M, Dd;

      if (Lv == 0) {
        break;
      }
      N++;
      M  = (Lv * 192) / 10;
      Dd = (M > Target[D]) ? M - Target[D] : Target[D] - M;
      if (Dd < Bd) {
        Bd   = Dd;
        Best = (UINT32)I;
      }
    }
    if (N < 8 || Bd > 150) {
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] EPSS cap: dom%lu LUT looks wrong (%u entries, nearest %u MHz off) - not writing anything\n", D, N, Bd));
      return;
    }
    Idx[D] = Best;
  }
  for (D = 0; D < 4; D++) {
    *(volatile UINT32 *)(UINTN)(Base[D] + 0x320) = Idx[D];
  }
  if (FirstCall) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] EPSS cap: performance states set to %u/%u/%u/%u (readback %u/%u/%u/%u)\n", Idx[0], Idx[1], Idx[2], Idx[3],
            *(volatile UINT32 *)(UINTN)(Base[0] + 0x320) & 0x3F, *(volatile UINT32 *)(UINTN)(Base[1] + 0x320) & 0x3F,
            *(volatile UINT32 *)(UINTN)(Base[2] + 0x320) & 0x3F, *(volatile UINT32 *)(UINTN)(Base[3] + 0x320) & 0x3F));
    *(volatile UINT32 *)(UINTN)0xD7FF0450ULL = 0x45505300U | (Idx[0] & 0xF) | ((Idx[1] & 0xF) << 4);   // "EPS" marker for the pstore/RAM log
  }
}

// poll *(Addr) & Mask == Want for up to Us microseconds; returns TRUE on match
STATIC BOOLEAN
PcPoll (IN UINT64 Addr, IN UINT32 Mask, IN UINT32 Want, IN UINTN Us)
{
  UINTN I;

  for (I = 0; I < Us; I++) {
    if ((MMR (Addr) & Mask) == Want) {
      return TRUE;
    }
    gBS->Stall (1);
  }
  return (MMR (Addr) & Mask) == Want;
}

STATIC VOID
PcGpio (IN UINT32 N, IN UINT32 Cfg, IN INT32 OutLevel)
{
  UINT64 B = TLMM_B + 0x1000ULL * N;

  if (OutLevel >= 0) {
    MMW (B + 4, OutLevel ? 2 : 0);          // set output level before enabling the driver
  }
  MMW (B, Cfg);
  PL ("gpio%u cfg=0x%x io=0x%x\n", N, MMR (B), MMR (B + 4));
}

#define PC_SKIP_RAILS 0   // test: rely on the rails Android left voted in AOP (warm reset keeps them)
STATIC VOID
PcRail (IN CONST CHAR8 *Name, IN UINT32 Uv)
{
  if (PC_SKIP_RAILS) { PL ("rail %a: skipped (PC_SKIP_RAILS)\n", Name); return; }
  UINT32 A = CmdDbAddr (Name);

  if (A == 0) {
    PL ("rail %a: not in cmd-db\n", Name);
    return;
  }
  PL ("rail %a addr=0x%x -> %u mV\n", Name, A, Uv / 1000);
  RpmhWrite (A + 0x0, Uv / 1000);
  RpmhWrite (A + 0x4, 1);
}

// VRM vote in Android's order for the WCN7850 LDOs: voltage, mode 7 (HPM), enable (2026-10-16 boot trace: cnss sets ldob15 + ldok6 this way)
STATIC VOID
PcRailHpm (IN CONST CHAR8 *Name, IN UINT32 Uv)
{
  if (PC_SKIP_RAILS) { PL ("rail %a: skipped (PC_SKIP_RAILS)\n", Name); return; }
  UINT32 A = CmdDbAddr (Name);

  if (A == 0) {
    PL ("rail %a: not in cmd-db\n", Name);
    return;
  }
  PL ("rail %a addr=0x%x -> %u mV, HPM\n", Name, A, Uv / 1000);
  RpmhWrite (A + 0x0, Uv / 1000);
  RpmhWrite (A + 0x8, 7);
  RpmhWrite (A + 0x4, 1);
}

// same, with an explicit RPMh mode (LDO: 3 retention / 4 LPM / 7 HPM; SMPS: 7 = PWM)
STATIC VOID
PcRailMode (IN CONST CHAR8 *Name, IN UINT32 Uv, IN UINT32 Mode)
{
  if (PC_SKIP_RAILS) { PL ("rail %a: skipped (PC_SKIP_RAILS)\n", Name); return; }
  UINT32 A = CmdDbAddr (Name);

  if (A == 0) {
    PL ("rail %a: not in cmd-db\n", Name);
    return;
  }
  PL ("rail %a addr=0x%x -> %u mV, mode %u\n", Name, A, Uv / 1000, Mode);
  RpmhWrite (A + 0x0, Uv / 1000);
  RpmhWrite (A + 0x8, Mode);
  RpmhWrite (A + 0x4, 1);
}

STATIC VOID
PcGdsc (IN UINT64 Gdscr, IN UINT32 Mask, IN CONST CHAR8 *Name)
{
  UINT64 Ctrl = GCC_B + 0x5214C;

  MMW (Ctrl, MMR (Ctrl) & ~Mask);           // drop the SW collapse vote
  MMW (GCC_B + Gdscr, MMR (GCC_B + Gdscr) & ~1U);
  PL ("gdsc %a: gdscr=0x%08x on=%d\n", Name, MMR (GCC_B + Gdscr), PcPoll (GCC_B + Gdscr, 0x80000000, 0x80000000, 20000));
}

STATIC VOID
PcRcgUpdate (IN UINT64 Cmd, IN UINT32 Cfg, IN CONST CHAR8 *Name)
{
  MMW (GCC_B + Cmd + 4, Cfg);
  MMW (GCC_B + Cmd, MMR (GCC_B + Cmd) | 2);     // root enable
  MMW (GCC_B + Cmd, MMR (GCC_B + Cmd) | 1);     // update
  PL ("rcg %a: update done=%d cmd=0x%08x cfg=0x%08x\n", Name, PcPoll (GCC_B + Cmd, 1, 0, 2000), MMR (GCC_B + Cmd), MMR (GCC_B + Cmd + 4));
}

STATIC VOID
PcClkHalt (IN UINT64 Halt, IN CONST CHAR8 *Name)
{
  PL ("clk %a: halt=0x%08x on=%d\n", Name, MMR (GCC_B + Halt), PcPoll (GCC_B + Halt, 0x80000000, 0, 2000));
}

// Display bring-up diagnostics (read-only): are the MDSS clocks / MDP still alive at MuChain time?  Each read is announced first so a
// bus hang leaves its address as the last log line.
STATIC VOID
DispProbe (VOID)
{
  STATIC CONST struct { UINT64 Base; CONST CHAR8 *Name; UINT32 Off; } Regs[] = {
    { 0x00100000ULL, "gcc_disp_hf_axi_clk", 0x2700C },
    { 0x00100000ULL, "gcc_disp_ahb (sleep/vote en 0x52008)", 0x52008 },
    { 0x0AF00000ULL, "dispcc mdss_ahb_clk", 0x80A4 },
    { 0x0AF00000ULL, "dispcc mdss_byte0_clk", 0x8028 },
    { 0x0AF00000ULL, "dispcc mdss_byte0_intf_clk", 0x802C },
    { 0x0AF00000ULL, "dispcc 0x8004", 0x8004 },
    { 0x0AF00000ULL, "dispcc 0x8008", 0x8008 },
    { 0x0AF00000ULL, "dispcc 0x800c", 0x800C },
    { 0x0AF00000ULL, "dispcc 0x8010", 0x8010 },
    { 0x0AF00000ULL, "dispcc 0x8014", 0x8014 },
    { 0x0AF00000ULL, "dispcc 0x8018", 0x8018 },
    { 0x0AF00000ULL, "dispcc 0x801c", 0x801C },
    { 0x0AF00000ULL, "dispcc 0x8020", 0x8020 },
    { 0x0AF00000ULL, "dispcc 0x8024", 0x8024 },
    { 0x0AF00000ULL, "dispcc mdp_clk_src cmd", 0x80D8 },
    { 0x0AF00000ULL, "dispcc pclk0_src cmd", 0x80A8 },
    { 0x0AF00000ULL, "dispcc byte0_src cmd", 0x8108 },
    { 0x0AF00000ULL, "dispcc mdss_gdsc (0x9000)", 0x9000 },
    { 0x0AE00000ULL, "MDSS hw_version", 0x0 },
    { 0x0AE00000ULL, "MDSS hw_intr_status", 0x10 },
  };
  UINT32  I;

  PcEnsureMmio (0x0AF00000ULL, 0x20000, "DISPCC");
  PcEnsureMmio (0x0AE00000ULL, 0x100000, "MDSS");
  for (I = 0; I < sizeof (Regs) / sizeof (Regs[0]); I++) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] DISP read %a @0x%lx ...\n", Regs[I].Name, Regs[I].Base + Regs[I].Off));
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] DISP %a = 0x%08x\n", Regs[I].Name, MMR (Regs[I].Base + Regs[I].Off)));
  }
  {
    // is the display power domain (MMCX) just voted down?  vote it back up through RPMh (ARC level, active set) and look again
    UINT32  Mm = CmdDbAddr ("mmcx.lvl");
    UINT32  Lv;
    STATIC CONST UINT32  Levels[] = { 1, 2, 3, 4 };   // Android votes mmcx.lvl with small level indices (1/3), not 128/256

    DEBUG ((DEBUG_ERROR, "[MUCHAIN] DISP mmcx.lvl addr=0x%x\n", Mm));
    if (Mm != 0) {
      for (Lv = 0; Lv < sizeof (Levels) / sizeof (Levels[0]); Lv++) {
        BOOLEAN Ok = RpmhWrite (Mm, Levels[Lv]);
        gBS->Stall (20000);
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] DISP mmcx.lvl <- %u (%d): MDSS hw_version=0x%08x dispcc ahb=0x%08x mdp_cmd=0x%08x gdsc=0x%08x\n", Levels[Lv], Ok,
                MMR (0x0AE00000ULL), MMR (0x0AF080A4ULL), MMR (0x0AF080D8ULL), MMR (0x0AF09000ULL)));
      }
    }
    // is the MDP state still there?  INTF_1/INTF_2 (the DSI interfaces), CTL_0, MIXER_0, DSC, PP, twice 50 ms apart (a running timing engine counts frames)
    {
      STATIC CONST struct { UINT64 Off; UINT32 Len; CONST CHAR8 *Name; } Blk[] = {
        { 0x36000, 0x100, "INTF_1" }, { 0x37000, 0x100, "INTF_2" }, { 0x16000, 0x100, "CTL_0" }, { 0x45000, 0x80, "MIXER_0" },
        { 0x6A000, 0x40, "PP_0" }, { 0x81000, 0x40, "DSC_0" }, { 0x0, 0x40, "TOP" }, { 0x100, 0x100, "TOP1" }, { 0x200, 0x100, "TOP2" },
      };
      UINT32  B, W, Pass;

      for (Pass = 0; Pass < 2; Pass++) {
        for (B = 0; B < sizeof (Blk) / sizeof (Blk[0]); B++) {
          for (W = 0; W < Blk[B].Len; W += 16) {
            UINT64 A = 0x0AE00000ULL + Blk[B].Off + W;
            DEBUG ((DEBUG_ERROR, "[MUCHAIN] SDE p%u %a+0x%02x: %08x %08x %08x %08x\n", Pass, Blk[B].Name, W,
                    MMR (A), MMR (A + 4), MMR (A + 8), MMR (A + 12)));
          }
        }
        gBS->Stall (50000);
      }
    }
  }
}

#include <Protocol/FirmwareVolume2.h>
#include <Protocol/LoadedImage.h>

// The 31 dispcc (AF00000) writes Android makes when the screen goes on (ftrace rwmmio capture, winboot\mmio_disp.txt, via refs\dispcc_writes.py):
// AHB / MDP / PLL0 / DSI byte+pixel+esc branch clocks.  After the MMCX rail comes back the dispcc is in its reset state, which is the state Android starts from.
STATIC VOID
DispClocksReplay (VOID)
{
  STATIC CONST struct { UINT32 Off; UINT32 Val; UINT32 DelayUs; } Seq[] = {
    { 0xC008, 0x80000001, 0 },    { 0x82E8, 0x2, 11 },         { 0x82EC, 0x100001, 8 },     { 0x82E8, 0x13, 5 },
    { 0x82E8, 0x0, 8 },           { 0xC004, 0x1, 6 },          { 0xC00C, 0x80000001, 9 },   { 0x80A4, 0x80000001, 216 },
    { 0x80D8, 0x80000002, 16 },   { 0x80DC, 0x100001, 6 },     { 0x80D8, 0x13, 5 },        { 0x80D8, 0x0, 6 },
    { 0x800C, 0x80000001, 4 },    { 0x8024, 0x80000001, 7 },   { 0x8018, 0x1, 8 },         { 0x0010, 0x440050, 1225 },
    { 0x0014, 0x5000, 1 },        { 0x0000, 0x4004, 4 },       { 0x0000, 0x2004, 4 },      { 0x0004, 0x1, 16 },
    { 0x0000, 0xC0000005, 13 },   { 0x80DC, 0x100105, 4 },     { 0x80D8, 0x11, 2 },         { 0x8038, 0x80000001, 5419 },
    { 0x810C, 0x201, 531 },       { 0x8108, 0x80000011, 3 },   { 0x80AC, 0x100, 13 },       { 0x80A8, 0x80000011, 3 },
    { 0x8028, 0x80000001, 14 },   { 0x8004, 0x80000001, 4 },   { 0x802C, 0x80000001, 4 },
  };
  UINT32  I;

  for (I = 0; I < sizeof (Seq) / sizeof (Seq[0]); I++) {
    if (Seq[I].DelayUs > 0) {
      gBS->Stall (Seq[I].DelayUs + (Seq[I].DelayUs > 100 ? 200 : 0));
    }
    MMW (0x0AF00000ULL + Seq[I].Off, Seq[I].Val);
  }
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP dispcc replay done: pll0 mode=0x%08x ahb=0x%08x byte0=0x%08x mdp=0x%08x\n", MMR (0x0AF00000ULL), MMR (0x0AF080A4ULL),
          MMR (0x0AF08028ULL), MMR (0x0AF08038ULL)));
}

#ifdef RM9_START_TEST
// Android's sde_rsc sequences (traced), replayed before a frame start: RSC driver at 0xAF20000, wrapper at 0xAF30000
STATIC VOID
RscW (IN UINT32 Off, IN UINT32 Val)
{
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] RSC w +0x%04x <- 0x%x\n", Off, Val));
  MMW (0x0AF20000ULL + Off, Val);
}

STATIC VOID
RscWW (IN UINT32 Off, IN UINT32 Val)
{
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] RSCW w +0x%04x <- 0x%x\n", Off, Val));
  MMW (0x0AF30000ULL + Off, Val);
}

STATIC VOID
RscPoll (IN UINT32 Off)
{
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] RSC r +0x%04x = 0x%08x\n", Off, MMR (0x0AF20000ULL + Off)));
}

STATIC VOID __attribute__((unused))
RscReplay (VOID)
{
  RscW (0x0004, 0x10); RscW (0x3020, 0); RscW (0x3024, 0); RscW (0x0000, 5); RscPoll (0x0024); gBS->Stall (200); RscPoll (0x0024);
  RscWW (0x0c20, 3); RscW (0x0004, 0x20); RscW (0x0004, 0x121); RscW (0x0040, 0); RscW (0x0004, 0x20); RscW (0x0004, 0x120);
  RscW (0x0000, 0); RscPoll (0x0000); RscW (0x0000, 1);
  RscW (0x0004, 0); RscW (0x0040, 0xe); RscW (0x0000, 1); RscWW (0x0c14, 0); RscW (0x0004, 0x121); RscW (0x0048, 0x10); RscW (0x0000, 1); RscPoll (0x0050);
  // per frame
  RscW (0x0000, 0); RscPoll (0x0000); RscW (0x0048, 1); RscW (0x0000, 1); RscPoll (0x0050);
}

#endif

// non-zero 16-byte groups of the MDP blocks that decide whether the panel is being fed (pipes, CTL, mixer, PP, INTF, DSC)
STATIC VOID
DispDump (IN CONST CHAR8 *Tag)
{
  STATIC CONST struct { UINT64 Off; UINT32 Len; CONST CHAR8 *Name; } Blk[] = {
    { 0x0, 0x40, "TOP" }, { 0x16000, 0x100, "CTL_0" }, { 0x45000, 0x100, "MIXER_0" },   // SSPP blocks hang when read (pipe clocks gated)
    { 0x6A000, 0x80, "PP_0" }, { 0x36000, 0x100, "INTF_1" }, { 0x37000, 0x100, "INTF_2" }, { 0x81000, 0x40, "DSC_0" },
    { 0x94000, 0x300, "DSI0" },   // (PP_0 at 0x69000 hangs on read beyond +0x130; do not probe)
    { 0x120000, 0x200, "RSC_DRV" }, { 0x130000, 0x80, "RSC_WRAP0" }, { 0x130400, 0x80, "RSC_WRAP4" },
  };
  STATIC CONST struct { UINT32 Addr; UINT32 Len; CONST CHAR8 *Name; } Abs[] = {
    { 0x00127000, 0x80, "GCC_DISP" }, { 0x00152000, 0x20, "GCC_52000" }, { 0x0AF00000, 0x20, "DISPCC0" }, { 0x0AF08000, 0x140, "DISPCC8" }, { 0x0AF09000, 0x20, "DISPCC9" },
  };
  UINT32  B, W;

  PcEnsureMmio (0x00100000ULL, 0x100000, "GCC");
  for (B = 0; B < sizeof (Abs) / sizeof (Abs[0]); B++) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] MDP %a block %a @0x%x ...\n", Tag, Abs[B].Name, Abs[B].Addr));
    for (W = 0; W < Abs[B].Len; W += 16) {
      UINT64  A = (UINT64)Abs[B].Addr + W;
      UINT32  V0 = MMR (A), V1 = MMR (A + 4), V2 = MMR (A + 8), V3 = MMR (A + 12);

      if ((V0 | V1 | V2 | V3) != 0) {
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] MDP %a %a+0x%03x: %08x %08x %08x %08x\n", Tag, Abs[B].Name, W, V0, V1, V2, V3));
      }
    }
  }
  for (B = 0; B < sizeof (Blk) / sizeof (Blk[0]); B++) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] MDP %a block %a @0x%lx ...\n", Tag, Blk[B].Name, 0x0AE00000ULL + Blk[B].Off));
    for (W = 0; W < Blk[B].Len; W += 16) {
      UINT64  A = 0x0AE00000ULL + Blk[B].Off + W;
      UINT32  V0 = MMR (A), V1 = MMR (A + 4), V2 = MMR (A + 8), V3 = MMR (A + 12);

      if ((V0 | V1 | V2 | V3) != 0) {
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] MDP %a %a+0x%03x: %08x %08x %08x %08x\n", Tag, Blk[B].Name, W, V0, V1, V2, V3));
      }
    }
  }
}

// \REFRESH.TXT: the bootloader's MDP pipe scans the splash framebuffer (Display_Reserved), but a command-mode panel only gets a new frame when CTL_0 START is written.
// ClockDxe is patched (0xa810) so that the MDSS power survives Mu's boot; here a periodic timer keeps firing START until ExitBootServices closes the event.
STATIC VOID EFIAPI
RefreshTick (IN EFI_EVENT Event, IN VOID *Context)
{
  MMW (0x0AE16000ULL + 0x1C, 1);
}

STATIC VOID
StartRefresher (VOID)
{
  EFI_EVENT   Ev = NULL;
  EFI_STATUS  S;

  PcEnsureMmio (0x0AE00000ULL, 0x100000, "MDSS");
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] REFRESH MDSS hw_version=0x%08x\n", MMR (0x0AE00000ULL)));
  S = gBS->CreateEvent (EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, RefreshTick, NULL, &Ev);
  if (!EFI_ERROR (S)) {
    S = gBS->SetTimer (Ev, TimerPeriodic, 300000);   // 30 ms
  }
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] REFRESH timer: %r\n", S));
}

// \START0.TXT: fire MDP CTL_0 START with nothing but the bootloader's own display state (no votes, no replay, no DisplayDxe) and watch the INTF frame counters
STATIC VOID
StartProbe0 (VOID)
{
  UINT32  I;

  PcEnsureMmio (0x0AE00000ULL, 0x100000, "MDSS");
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] START0 hw_version=0x%08x flush=0x%08x intf1 a0..ac=%08x %08x %08x %08x\n", MMR (0x0AE00000ULL), MMR (0x0AE16018ULL),
          MMR (0x0AE360A0ULL), MMR (0x0AE360A4ULL), MMR (0x0AE360A8ULL), MMR (0x0AE360ACULL)));
  for (I = 0; I < 3; I++) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] START0 #%u ...\n", I));
    MMW (0x0AE16000ULL + 0x1C, 1);
    gBS->Stall (50000);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] START0 #%u ok flush=0x%08x intf1 a0..ac=%08x %08x %08x %08x\n", I, MMR (0x0AE16018ULL),
            MMR (0x0AE360A0ULL), MMR (0x0AE360A4ULL), MMR (0x0AE360A8ULL), MMR (0x0AE360ACULL)));
  }
  // visible test pattern straight into the splash framebuffer (Display_Reserved, the memory the bootloader's MDP pipe scans), then keep firing START
  {
    volatile UINT32  *Fb = (volatile UINT32 *)(UINTN)0xE3940000ULL;
    UINT32           Row, Col, Rows = 2480, Cols = 1116, N;

    for (Row = 0; Row < Rows; Row++) {
      for (Col = 0; Col < Cols; Col++) {
        UINT32 Px = (Row < Rows / 3) ? 0x00FF0000 : (Row < 2 * Rows / 3 ? 0x0000FF00 : 0x000000FF);   // red / green / blue bands (BGRX)
        if (Col < 40) Px = 0x00FFFFFF;                                                                   // white strip at the left edge
        Fb[(UINTN)Row * Cols + Col] = Px;
      }
    }
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] START0 pattern drawn\n"));
    for (N = 0; N < 100; N++) {
      MMW (0x0AE16000ULL + 0x1C, 1);
      gBS->Stall (50000);
    }
#define SMP(tag) DEBUG ((DEBUG_ERROR, "[MUCHAIN] START0 %a: dsi 08=%08x 0c=%08x a0=%08x 120=%08x | pp 30=%08x 3c=%08x | intf a4=%08x\n", tag, \
        MMR (0x0AE94008ULL), MMR (0x0AE9400CULL), MMR (0x0AE940A0ULL), MMR (0x0AE94120ULL), MMR (0x0AE69030ULL), MMR (0x0AE6903CULL), MMR (0x0AE360A4ULL)))
    SMP ("after loop");
    MMW (0x0AE16000ULL + 0x1C, 1);
    SMP ("0ms after START");
    gBS->Stall (20000);
    SMP ("20ms after START");
    gBS->Stall (500000);
    SMP ("520ms after START");
    MMW (0x0AE69030ULL, 0x8000FFFF);
    MMW (0x0AE6A030ULL, 0x8000FFFF);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] START0 PP69+30=%08x PP6A+30=%08x PP6A+0..: %08x %08x %08x %08x\n", MMR (0x0AE69030ULL), MMR (0x0AE6A030ULL), MMR (0x0AE6A000ULL), MMR (0x0AE6A004ULL), MMR (0x0AE6A008ULL), MMR (0x0AE6A00CULL)));
    SMP ("autorefresh cfg written");
    gBS->Stall (500000);
    SMP ("+500ms");
    for (N = 0; N < 20; N++) {
      Fb[N * Cols + 100] = 0x00FFFF00 + N;   // touch the framebuffer; no START from now on
    }
    gBS->Stall (1000000);
    SMP ("+1.5s");
  }
}

// \DISP.TXT: start Qualcomm's stock DisplayDxe from here (it is in the firmware volume but not dispatched: its depex is FALSE).  Mu's early DXE phase
// is a bad place for it (no timer ticks, display power gone); here the MMCX rail can be voted back first and the ELR profiler shows where it sits.
STATIC VOID
LateDisplay (VOID)
{
  STATIC CONST EFI_GUID  DispGuid = { 0x4138022F, 0x06C7, 0x4F79, { 0x9C, 0x94, 0x7E, 0x33, 0xB5, 0x11, 0xA4, 0xE7 } };
  EFI_HANDLE             *H = NULL;
  UINTN                  N = 0, I;
  EFI_STATUS             S;
  VOID                   *Buf = NULL;
  UINTN                  Sz = 0;
  EFI_HANDLE             Img = NULL;
  UINT32                 Mm = CmdDbAddr ("mmcx.lvl");

  PcEnsureMmio (0x0AF00000ULL, 0x20000, "DISPCC");
  PcEnsureMmio (0x0AE00000ULL, 0x100000, "MDSS");
  PcEnsureMmio (0x0AF20000ULL, 0x20000, "SDE_RSC");
  if (Mm != 0) {
    BOOLEAN Ok = RpmhWrite (Mm, 1);
    gBS->Stall (20000);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP mmcx.lvl <- 1 (%d): MDSS hw_version=0x%08x\n", Ok, MMR (0x0AE00000ULL)));
  }
  {
    // Android's interconnect (BCM) votes when the display comes up: the MDP must reach DDR through the multimedia NoC, which is gated without MM0
    STATIC CONST struct { CONST CHAR8 *Name; UINT32 Val; } Bcm[] = {
      { "SH1", 0x20000001 }, { "SH0", 0x63032FF9 }, { "MM0", 0x6000084F }, { "MC0", 0x60ED5723 }, { "ACV", 0x60000001 },
    };
    UINT32  K;

    for (K = 0; K < sizeof (Bcm) / sizeof (Bcm[0]); K++) {
      UINT32 A = CmdDbAddr (Bcm[K].Name);

      if (A != 0) {
        BOOLEAN Ok = RpmhWrite (A, Bcm[K].Val);
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP BCM %a @0x%x <- 0x%08x: %d\n", Bcm[K].Name, A, Bcm[K].Val, Ok));
      } else {
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP BCM %a not in cmd-db\n", Bcm[K].Name));
      }
    }
    gBS->Stall (20000);
  }
  DispClocksReplay ();
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP DSI ctrl reg 0x84= 0x%08x (AE94084)\n", MMR (0x0AE94084ULL)));
  {
    // single-register probes of the DSI controller, announced before each access so a stall leaves its address as the last log line
    STATIC CONST UINT32  Offs[] = { 0x000, 0x004, 0x008, 0x084, 0x0A8, 0x110 };
    UINT32               K;

    for (K = 0; K < sizeof (Offs) / sizeof (Offs[0]); K++) {
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP DSI read  +0x%03x ...\n", Offs[K]));
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP DSI read  +0x%03x = 0x%08x\n", Offs[K], MMR (0x0AE94000ULL + Offs[K])));
    }
    for (K = 0; K < sizeof (Offs) / sizeof (Offs[0]); K++) {
      UINT32 V = MMR (0x0AE94000ULL + Offs[K]);
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP DSI write +0x%03x <- 0x%08x ...\n", Offs[K], V));
      MMW (0x0AE94000ULL + Offs[K], V);
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP DSI write +0x%03x done\n", Offs[K]));
    }
    {
      UINT32 V = (MMR (0x0AE94084ULL) & ~0xFU) | 4;   // what DisplayDxe writes right before it hangs (mode 3 -> value 4)
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP DSI write +0x084 <- 0x%08x (DisplayDxe's value) ...\n", V));
      MMW (0x0AE94084ULL, V);
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP DSI write +0x084 done, reads back 0x%08x\n", MMR (0x0AE94084ULL)));
    }
  }
  S = gBS->LocateHandleBuffer (ByProtocol, &gEfiFirmwareVolume2ProtocolGuid, NULL, &N, &H);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP FV2 handles: %r n=%lu\n", S, (UINT64)N));
  for (I = 0; !EFI_ERROR (S) && I < N && Buf == NULL; I++) {
    EFI_FIRMWARE_VOLUME2_PROTOCOL  *Fv = NULL;
    UINT32                         Auth = 0;

    if (EFI_ERROR (gBS->HandleProtocol (H[I], &gEfiFirmwareVolume2ProtocolGuid, (VOID **)&Fv)) || Fv == NULL) {
      continue;
    }
    if (!EFI_ERROR (Fv->ReadSection (Fv, &DispGuid, EFI_SECTION_PE32, 0, &Buf, &Sz, &Auth))) {
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP DisplayDxe PE32 section: %lu bytes in FV handle %lu\n", (UINT64)Sz, (UINT64)I));
    } else {
      Buf = NULL;
    }
  }
  if (Buf == NULL) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP DisplayDxe not found in any FV\n"));
    return;
  }
  S = gBS->LoadImage (FALSE, gImageHandle, NULL, Buf, Sz, &Img);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP LoadImage: %r\n", S));
  if (EFI_ERROR (S)) {
    return;
  }
  StartProfiler ();
  S = gBS->StartImage (Img, NULL, NULL);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP StartImage returned: %r  MDSS hw_version=0x%08x\n", S, MMR (0x0AE00000ULL)));
#ifdef RM9_START_TEST
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP TOP clk-ctrl before: 144=0x%08x 150=0x%08x 154=0x%08x (Android/ABL: 0x103e 3 1)\n",
          MMR (0x0AE00144ULL), MMR (0x0AE00150ULL), MMR (0x0AE00154ULL)));
  MMW (0x0AE00144ULL, 0x103E);
  MMW (0x0AE00150ULL, 3);
  MMW (0x0AE00154ULL, 1);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP TOP clk-ctrl after: 144=0x%08x 150=0x%08x 154=0x%08x\n",
          MMR (0x0AE00144ULL), MMR (0x0AE00150ULL), MMR (0x0AE00154ULL)));
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP START A (right after DisplayDxe) ...\n"));
  MMW (0x0AE16000ULL + 0x1C, 1);
  gBS->Stall (50000);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP START A ok, flush=0x%08x\n", MMR (0x0AE16018ULL)));
#endif
  {
    EFI_GRAPHICS_OUTPUT_PROTOCOL  *Gop = NULL;

    S = gBS->LocateProtocol (&gEfiGraphicsOutputProtocolGuid, NULL, (VOID **)&Gop);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP GOP: %r %p\n", S, Gop));
    if (!EFI_ERROR (S) && Gop != NULL && Gop->Mode != NULL && Gop->Mode->Info != NULL) {
      UINT32  W = Gop->Mode->Info->HorizontalResolution, Ht = Gop->Mode->Info->VerticalResolution;

      DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP GOP mode %u/%u %ux%u stride=%u fb=0x%lx size=0x%lx fmt=%u\n", Gop->Mode->Mode, Gop->Mode->MaxMode, W, Ht,
              Gop->Mode->Info->PixelsPerScanLine, (UINT64)Gop->Mode->FrameBufferBase, (UINT64)Gop->Mode->FrameBufferSize, (UINT32)Gop->Mode->Info->PixelFormat));
      DispDump ("pre-blt");
#ifdef RM9_START_TEST
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP START B (after the read-only dump) ...\n"));
      MMW (0x0AE16000ULL + 0x1C, 1);
      gBS->Stall (50000);
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP START B ok, flush=0x%08x\n", MMR (0x0AE16018ULL)));
#endif
      {
        EFI_GRAPHICS_OUTPUT_BLT_PIXEL  Px;

        Px.Blue = 0; Px.Green = 0; Px.Red = 255; Px.Reserved = 0;
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP Blt fill red ...\n"));
        S = Gop->Blt (Gop, &Px, EfiBltVideoFill, 0, 0, 0, 0, W, Ht, 0);
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP Blt fill red: %r\n", S));
        gBS->Stall (200000);
        DispDump ("post-blt");
#ifdef RM9_START_TEST
        // CTL_0 START kills the SoC instantly (no timer tick, no exception) in the DisplayDxe-configured state: kept for experiments only
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP CTL_0 START ...\n"));
        MMW (0x0AE16000ULL + 0x1C, 1);
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] LATEDISP CTL_0 START written\n"));
        gBS->Stall (200000);
        DispDump ("post-start");
#endif
      }
    }
  }
}

#define SPMI_CHNLS  0x0C500000ULL

// single-byte SPMI register write through the arbiter write channel of the apid (EE0-owned peripherals only); Linux spmi-pmic-arb.c v7
STATIC BOOLEAN
SpmiWriteByte (IN UINT32 Sid, IN UINT32 Addr16, IN UINT8 Val)
{
  UINT32  Ppid = (Sid << 8) | (Addr16 >> 8);
  UINT32  Apid = mSpmiApid[Ppid & 0xFFF];
  UINT64  Off;
  UINT32  I, St = 0;

  if (Apid == 0) {
    return FALSE;
  }
  Apid -= 1;
  Off = SPMI_CHNLS + 0x1000ULL * Apid;
  *(volatile UINT32 *)(UINTN)(Off + 0x10) = Val;                                   // WDATA0
  *(volatile UINT32 *)(UINTN)(Off + 0x00) = (0U << 27) | ((Addr16 & 0xFF) << 4) | 0;   // EXT_WRITEL, 1 byte
  for (I = 0; I < 1000; I++) {
    St = *(volatile UINT32 *)(UINTN)(Off + 0x08);
    if (St & 1) {
      break;
    }
    gBS->Stall (1);
  }
  if (!(St & 1) || (St & 0xE)) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] SPMI write sid=%u addr=0x%x failed status=0x%x\n", Sid, Addr16, St));
    return FALSE;
  }
  return TRUE;
}

// AOSS QMP (aoss-qmp @0xc300000, kicked through IPCC @0x406000 client 0 / signal 0), same handshake + 64-byte messages as Linux qcom_aoss.c.
// cnss sends "wlan_pdc" messages to AOP before powering the WCN7850 (2026-10-16 kprobe capture, winboot/boottrace3/kprobes.txt).
#define QMP_B        0x0C300000ULL
#define IPCC_B       0x00406000ULL
STATIC UINT32  mQmpOff;

STATIC VOID
QmpKick (VOID)
{
  MMW (IPCC_B + 0x0C, 0);                                           // IPCC_REG_SEND_ID = (client 0 << 16) | signal 0
}

STATIC BOOLEAN
QmpWait (IN UINT64 Reg, IN UINT32 Want, IN UINT32 Ms)
{
  UINT32  I;

  for (I = 0; I < Ms * 10; I++) {
    if (MMR (Reg) == Want) {
      return TRUE;
    }
    gBS->Stall (100);
  }
  return MMR (Reg) == Want;
}

STATIC BOOLEAN
QmpOpen (VOID)
{
  BOOLEAN  A, B, C;

  PcEnsureMmio (QMP_B, 0x1000, "AOSS_QMP");
  PcEnsureMmio (IPCC_B, 0x1000, "IPCC");
  PL ("qmp desc: magic=0x%x ver=%u ucore link=0x%x/0x%x ch=0x%x/0x%x mbox 0x%x@0x%x | mcore link=0x%x/0x%x ch=0x%x/0x%x mbox 0x%x@0x%x\n",
      MMR (QMP_B), MMR (QMP_B + 0x4), MMR (QMP_B + 0xC), MMR (QMP_B + 0x10), MMR (QMP_B + 0x14), MMR (QMP_B + 0x18), MMR (QMP_B + 0x1C),
      MMR (QMP_B + 0x20), MMR (QMP_B + 0x24), MMR (QMP_B + 0x28), MMR (QMP_B + 0x2C), MMR (QMP_B + 0x30), MMR (QMP_B + 0x34), MMR (QMP_B + 0x38));
  if ((MMR (QMP_B) != 0x4D41494C) || (MMR (QMP_B + 0x4) != 1) || (MMR (QMP_B + 0x34) < 0x44)) {
    PL ("qmp: bad descriptor\n");
    return FALSE;
  }
  mQmpOff = MMR (QMP_B + 0x38);
  if ((MMR (QMP_B + 0x24) == 0xFFFF) && (MMR (QMP_B + 0x30) == 0xFFFF) && (MMR (QMP_B + 0x14) == 0xFFFF)) {
    PL ("qmp: link already up\n");
    return TRUE;
  }
  MMW (QMP_B + 0x10, MMR (QMP_B + 0xC));                            // ack AOP's link state
  MMW (QMP_B + 0x24, 0xFFFF);                                       // our link up
  QmpKick ();
  A = QmpWait (QMP_B + 0x28, 0xFFFF, 1000);
  MMW (QMP_B + 0x2C, 0xFFFF);                                       // our channel up
  QmpKick ();
  B = QmpWait (QMP_B + 0x14, 0xFFFF, 1000);
  MMW (QMP_B + 0x18, 0xFFFF);                                       // ack AOP's channel
  QmpKick ();
  C = QmpWait (QMP_B + 0x30, 0xFFFF, 1000);
  PL ("qmp open: link_ack=%d ucore_ch_up=%d mcore_ch_ack=%d\n", A, B, C);
  return A && B && C;
}

STATIC BOOLEAN
QmpSend (IN CONST CHAR8 *Msg)
{
  UINT32   Buf[16];
  UINT32   I;
  BOOLEAN  Ok;

  ZeroMem (Buf, sizeof (Buf));
  CopyMem (Buf, Msg, MIN (AsciiStrLen (Msg), sizeof (Buf) - 1));
  if (!QmpWait (QMP_B + mQmpOff, 0, 100)) {
    PL ("qmp busy (len=0x%x), skipping: %a\n", MMR (QMP_B + mQmpOff), Msg);
    return FALSE;
  }
  for (I = 0; I < 16; I++) {
    MMW (QMP_B + mQmpOff + 4 + 4 * I, Buf[I]);
  }
  MMW (QMP_B + mQmpOff, sizeof (Buf));
  (VOID)MMR (QMP_B + mQmpOff);
  QmpKick ();
  Ok = QmpWait (QMP_B + mQmpOff, 0, 1000);
  if (!Ok) {
    MMW (QMP_B + mQmpOff, 0);
  }
  PL ("qmp send %a: %a\n", Ok ? "ok" : "TIMEOUT", Msg);
  return Ok;
}

// PCIe CRM (crm@1d01000, base 0x1d01000) writes captured from Android's boot-time ftrace (winboot/boottrace2, 2026-10-16).
// Generated by hand from pcie_crm_writes.txt; va 0xffff8000087f0000 = phys 0x1d01000 (confirmed by crm.ko register tables).

// crm_probe (0.388 s): sw_drv_perf_ol +0x11e0.., sw_drv_bw_vote +0x1580.. <- 1
STATIC CONST UINT32  mPcieCrmProbe[18][2] = {
  { 0x1D021E0, 0x00000001 }, { 0x1D021E4, 0x00000001 }, { 0x1D02580, 0x00000001 }, { 0x1D02584, 0x00000001 },
  { 0x1D02588, 0x00000001 }, { 0x1D0258C, 0x00000001 }, { 0x1D02590, 0x00000001 }, { 0x1D02594, 0x00000001 },
  { 0x1D02598, 0x00000001 }, { 0x1D0259C, 0x00000001 }, { 0x1D025A0, 0x00000001 }, { 0x1D025A4, 0x00000001 },
  { 0x1D025A8, 0x00000001 }, { 0x1D025AC, 0x00000001 }, { 0x1D025B0, 0x00000001 }, { 0x1D025B4, 0x00000001 },
  { 0x1D025B8, 0x00000001 }, { 0x1D025BC, 0x00000001 },
};

// crm_write_pwr_states (1.670 s, before msm_pcie_enable_link): two channel tables, trigger +0x1020 <- 1 then 2
STATIC CONST UINT32  mPcieCrmPwr[182][2] = {
  { 0x1D01200, 0x00000000 }, { 0x1D01240, 0x00000000 }, { 0x1D01280, 0x00000000 }, { 0x1D01800, 0x00000000 },
  { 0x1D01840, 0x00000000 }, { 0x1D01204, 0x00000000 }, { 0x1D01244, 0x00000000 }, { 0x1D01284, 0x00000000 },
  { 0x1D01804, 0x00000000 }, { 0x1D01844, 0x00000000 }, { 0x1D012C0, 0x60004001 }, { 0x1D01340, 0x60004001 },
  { 0x1D01880, 0x60000000 }, { 0x1D01900, 0x60000000 }, { 0x1D01980, 0x60000000 }, { 0x1D012C4, 0x60004001 },
  { 0x1D01344, 0x60004001 }, { 0x1D01884, 0x60000000 }, { 0x1D01904, 0x60000000 }, { 0x1D01984, 0x60000000 },
  { 0x1D012C8, 0x60000001 }, { 0x1D01348, 0x60000001 }, { 0x1D01888, 0x60000000 }, { 0x1D01908, 0x60000000 },
  { 0x1D01988, 0x60000000 }, { 0x1D012CC, 0x60004001 }, { 0x1D0134C, 0x60004001 }, { 0x1D0188C, 0x60000000 },
  { 0x1D0190C, 0x60000000 }, { 0x1D0198C, 0x60000000 }, { 0x1D012D0, 0x00000000 }, { 0x1D01350, 0x00000000 },
  { 0x1D01890, 0x00000000 }, { 0x1D01910, 0x00000000 }, { 0x1D01990, 0x00000000 }, { 0x1D012D4, 0x60000001 },
  { 0x1D01354, 0x60000001 }, { 0x1D01894, 0x60000000 }, { 0x1D01914, 0x60000000 }, { 0x1D01994, 0x60000000 },
  { 0x1D012D8, 0x00000000 }, { 0x1D01358, 0x00000000 }, { 0x1D01898, 0x00000000 }, { 0x1D01918, 0x00000000 },
  { 0x1D01998, 0x00000000 }, { 0x1D012DC, 0x00000000 }, { 0x1D0135C, 0x00000000 }, { 0x1D0189C, 0x00000000 },
  { 0x1D0191C, 0x00000000 }, { 0x1D0199C, 0x00000000 }, { 0x1D012E0, 0x00000000 }, { 0x1D01360, 0x00000000 },
  { 0x1D018A0, 0x00000000 }, { 0x1D01920, 0x00000000 }, { 0x1D019A0, 0x00000000 }, { 0x1D012E4, 0x00000000 },
  { 0x1D01364, 0x00000000 }, { 0x1D018A4, 0x00000000 }, { 0x1D01924, 0x00000000 }, { 0x1D019A4, 0x00000000 },
  { 0x1D012E8, 0x00000000 }, { 0x1D01368, 0x00000000 }, { 0x1D018A8, 0x00000000 }, { 0x1D01928, 0x00000000 },
  { 0x1D019A8, 0x00000000 }, { 0x1D012EC, 0x00000000 }, { 0x1D0136C, 0x00000000 }, { 0x1D018AC, 0x00000000 },
  { 0x1D0192C, 0x00000000 }, { 0x1D019AC, 0x00000000 }, { 0x1D012F0, 0x00000000 }, { 0x1D01370, 0x00000000 },
  { 0x1D018B0, 0x00000000 }, { 0x1D01930, 0x00000000 }, { 0x1D019B0, 0x00000000 }, { 0x1D012F4, 0x00000000 },
  { 0x1D01374, 0x00000000 }, { 0x1D018B4, 0x00000000 }, { 0x1D01934, 0x00000000 }, { 0x1D019B4, 0x00000000 },
  { 0x1D012F8, 0x00000000 }, { 0x1D01378, 0x00000000 }, { 0x1D018B8, 0x00000000 }, { 0x1D01938, 0x00000000 },
  { 0x1D019B8, 0x00000000 }, { 0x1D012FC, 0x00000000 }, { 0x1D0137C, 0x00000000 }, { 0x1D018BC, 0x00000000 },
  { 0x1D0193C, 0x00000000 }, { 0x1D019BC, 0x00000000 }, { 0x1D02020, 0x00000001 }, { 0x1D01208, 0x00000004 },
  { 0x1D01248, 0x00000004 }, { 0x1D01288, 0x00000000 }, { 0x1D01808, 0x00000000 }, { 0x1D01848, 0x00000000 },
  { 0x1D0120C, 0x00000000 }, { 0x1D0124C, 0x00000000 }, { 0x1D0128C, 0x00000000 }, { 0x1D0180C, 0x00000000 },
  { 0x1D0184C, 0x00000000 }, { 0x1D01300, 0x60004001 }, { 0x1D01380, 0x60004001 }, { 0x1D018C0, 0x60000000 },
  { 0x1D01940, 0x60000000 }, { 0x1D019C0, 0x60000000 }, { 0x1D01304, 0x60004001 }, { 0x1D01384, 0x60004001 },
  { 0x1D018C4, 0x60000000 }, { 0x1D01944, 0x60000000 }, { 0x1D019C4, 0x60000000 }, { 0x1D01308, 0x60000001 },
  { 0x1D01388, 0x60000001 }, { 0x1D018C8, 0x60000000 }, { 0x1D01948, 0x60000000 }, { 0x1D019C8, 0x60000000 },
  { 0x1D0130C, 0x60004001 }, { 0x1D0138C, 0x60004001 }, { 0x1D018CC, 0x60000000 }, { 0x1D0194C, 0x60000000 },
  { 0x1D019CC, 0x60000000 }, { 0x1D01310, 0x00000000 }, { 0x1D01390, 0x00000000 }, { 0x1D018D0, 0x00000000 },
  { 0x1D01950, 0x00000000 }, { 0x1D019D0, 0x00000000 }, { 0x1D01314, 0x60000001 }, { 0x1D01394, 0x60000001 },
  { 0x1D018D4, 0x60000000 }, { 0x1D01954, 0x60000000 }, { 0x1D019D4, 0x60000000 }, { 0x1D01318, 0x00000000 },
  { 0x1D01398, 0x00000000 }, { 0x1D018D8, 0x00000000 }, { 0x1D01958, 0x00000000 }, { 0x1D019D8, 0x00000000 },
  { 0x1D0131C, 0x00000000 }, { 0x1D0139C, 0x00000000 }, { 0x1D018DC, 0x00000000 }, { 0x1D0195C, 0x00000000 },
  { 0x1D019DC, 0x00000000 }, { 0x1D01320, 0x00000000 }, { 0x1D013A0, 0x00000000 }, { 0x1D018E0, 0x00000000 },
  { 0x1D01960, 0x00000000 }, { 0x1D019E0, 0x00000000 }, { 0x1D01324, 0x00000000 }, { 0x1D013A4, 0x00000000 },
  { 0x1D018E4, 0x00000000 }, { 0x1D01964, 0x00000000 }, { 0x1D019E4, 0x00000000 }, { 0x1D01328, 0x00000000 },
  { 0x1D013A8, 0x00000000 }, { 0x1D018E8, 0x00000000 }, { 0x1D01968, 0x00000000 }, { 0x1D019E8, 0x00000000 },
  { 0x1D0132C, 0x00000000 }, { 0x1D013AC, 0x00000000 }, { 0x1D018EC, 0x00000000 }, { 0x1D0196C, 0x00000000 },
  { 0x1D019EC, 0x00000000 }, { 0x1D01330, 0x00000000 }, { 0x1D013B0, 0x00000000 }, { 0x1D018F0, 0x00000000 },
  { 0x1D01970, 0x00000000 }, { 0x1D019F0, 0x00000000 }, { 0x1D01334, 0x00000000 }, { 0x1D013B4, 0x00000000 },
  { 0x1D018F4, 0x00000000 }, { 0x1D01974, 0x00000000 }, { 0x1D019F4, 0x00000000 }, { 0x1D01338, 0x00000000 },
  { 0x1D013B8, 0x00000000 }, { 0x1D018F8, 0x00000000 }, { 0x1D01978, 0x00000000 }, { 0x1D019F8, 0x00000000 },
  { 0x1D0133C, 0x00000000 }, { 0x1D013BC, 0x00000000 }, { 0x1D018FC, 0x00000000 }, { 0x1D0197C, 0x00000000 },
  { 0x1D019FC, 0x00000000 }, { 0x1D02020, 0x00000002 },
};

// crm_write_pwr_states (1.703 s, right after link up): next table, trigger +0x1020
STATIC CONST UINT32  mPcieCrmPost[91][2] = {
  { 0x1D01200, 0x00000003 }, { 0x1D01240, 0x00000003 }, { 0x1D01280, 0x00000000 }, { 0x1D01800, 0x00000000 },
  { 0x1D01840, 0x00000000 }, { 0x1D01204, 0x00000000 }, { 0x1D01244, 0x00000000 }, { 0x1D01284, 0x00000000 },
  { 0x1D01804, 0x00000000 }, { 0x1D01844, 0x00000000 }, { 0x1D012C0, 0x60004001 }, { 0x1D01340, 0x60004001 },
  { 0x1D01880, 0x60000000 }, { 0x1D01900, 0x60000000 }, { 0x1D01980, 0x60000000 }, { 0x1D012C4, 0x60004001 },
  { 0x1D01344, 0x60004001 }, { 0x1D01884, 0x60000000 }, { 0x1D01904, 0x60000000 }, { 0x1D01984, 0x60000000 },
  { 0x1D012C8, 0x60000001 }, { 0x1D01348, 0x60000001 }, { 0x1D01888, 0x60000000 }, { 0x1D01908, 0x60000000 },
  { 0x1D01988, 0x60000000 }, { 0x1D012CC, 0x60004001 }, { 0x1D0134C, 0x60004001 }, { 0x1D0188C, 0x60000000 },
  { 0x1D0190C, 0x60000000 }, { 0x1D0198C, 0x60000000 }, { 0x1D012D0, 0x00000000 }, { 0x1D01350, 0x00000000 },
  { 0x1D01890, 0x00000000 }, { 0x1D01910, 0x00000000 }, { 0x1D01990, 0x00000000 }, { 0x1D012D4, 0x60000001 },
  { 0x1D01354, 0x60000001 }, { 0x1D01894, 0x60000000 }, { 0x1D01914, 0x60000000 }, { 0x1D01994, 0x60000000 },
  { 0x1D012D8, 0x00000000 }, { 0x1D01358, 0x00000000 }, { 0x1D01898, 0x00000000 }, { 0x1D01918, 0x00000000 },
  { 0x1D01998, 0x00000000 }, { 0x1D012DC, 0x00000000 }, { 0x1D0135C, 0x00000000 }, { 0x1D0189C, 0x00000000 },
  { 0x1D0191C, 0x00000000 }, { 0x1D0199C, 0x00000000 }, { 0x1D012E0, 0x00000000 }, { 0x1D01360, 0x00000000 },
  { 0x1D018A0, 0x00000000 }, { 0x1D01920, 0x00000000 }, { 0x1D019A0, 0x00000000 }, { 0x1D012E4, 0x00000000 },
  { 0x1D01364, 0x00000000 }, { 0x1D018A4, 0x00000000 }, { 0x1D01924, 0x00000000 }, { 0x1D019A4, 0x00000000 },
  { 0x1D012E8, 0x00000000 }, { 0x1D01368, 0x00000000 }, { 0x1D018A8, 0x00000000 }, { 0x1D01928, 0x00000000 },
  { 0x1D019A8, 0x00000000 }, { 0x1D012EC, 0x00000000 }, { 0x1D0136C, 0x00000000 }, { 0x1D018AC, 0x00000000 },
  { 0x1D0192C, 0x00000000 }, { 0x1D019AC, 0x00000000 }, { 0x1D012F0, 0x00000000 }, { 0x1D01370, 0x00000000 },
  { 0x1D018B0, 0x00000000 }, { 0x1D01930, 0x00000000 }, { 0x1D019B0, 0x00000000 }, { 0x1D012F4, 0x00000000 },
  { 0x1D01374, 0x00000000 }, { 0x1D018B4, 0x00000000 }, { 0x1D01934, 0x00000000 }, { 0x1D019B4, 0x00000000 },
  { 0x1D012F8, 0x00000000 }, { 0x1D01378, 0x00000000 }, { 0x1D018B8, 0x00000000 }, { 0x1D01938, 0x00000000 },
  { 0x1D019B8, 0x00000000 }, { 0x1D012FC, 0x00000000 }, { 0x1D0137C, 0x00000000 }, { 0x1D018BC, 0x00000000 },
  { 0x1D0193C, 0x00000000 }, { 0x1D019BC, 0x00000000 }, { 0x1D02020, 0x00000001 },
};


STATIC BOOLEAN SmmuBypassSid (IN UINT32 Sid);   // defined with the touch code further down
STATIC VOID SmmuForgetSid (IN UINT32 Sid);
STATIC BOOLEAN mPcKeep = FALSE;   // production mode: leave PCIe0 + WCN7850 powered and the link up for Windows (\PCIE.TXT)
STATIC BOOLEAN mBhiMode = FALSE;  // NOBOOT + \BHITEST.TXT: PcieProbe runs ItsTest with the chip's BHI download as the MSI source (see BhiRun)
STATIC VOID    ItsTest (VOID);
STATIC UINT32  mRstP[0x700 / 4], mRstD[0x900 / 4], mRstH[0x1400 / 4], mBfP[0x700 / 4], mBfD[0x900 / 4], mBfH[0x1400 / 4];   // post-reset (pre-init) register snapshots, printed after the quiet window

STATIC VOID
PcieProbe (VOID)
{
  UINT32  I, V;
  UINT64  TWlan = 0, TCrm = 0, TPhy = 0, TPerst = 0;
  UINT32  N = (UINT32)(sizeof (mPciePhySeq) / sizeof (mPciePhySeq[0]));

  PL ("=== M2 start (phy seq %u entries)\n", N);
  PcEnsureMmio (GCC_B, 0x80000, "GCC");
  PcEnsureMmio (PARF_B, 0x8000, "PCIE0_WRAPPER");
  PcEnsureMmio (TLMM_B, 0x1000000, "TLMM");
  PcEnsureMmio (0x01F00000ULL, 0x100000, "TCSR");
  PcEnsureMmio (DBI_B, 0x200000, "PCIE0_AXI");
  PcEnsureMmio (0x60200000ULL, 0x3E00000, "PCIE0_MEM");                // IO/MEM window behind the RC (EP BARs); without a mapping the first BAR access is a translation fault
  PL ("pre: gcc gpll0=0x%08x pcie_0_gdsc=0x%08x phy_gdsc=0x%08x vote_en=0x%08x/0x%08x core_bcr=0x%x tcsr_clkref=0x%08x\n",
      MMR (GCC_B + 0x0), MMR (GCC_B + 0x6B004), MMR (GCC_B + 0x6C000), MMR (GCC_B + 0x52008), MMR (GCC_B + 0x52000),
      MMR (GCC_B + 0x6B000), MMR (TCSR_CLKREF));
  PL ("pre: reading gpio16 cfg\n");
  PL ("pre: gpio16 cfg=0x%x\n", MMR (TLMM_B + 0x10000));
  PL ("pre: gpio16 io=0x%x\n", MMR (TLMM_B + 0x10004));
  PL ("pre: gpio94 cfg=0x%x\n", MMR (TLMM_B + 0x5E000));
  PL ("pre: gpio94 io=0x%x\n", MMR (TLMM_B + 0x5E004));
  PL ("pre: gpio95 cfg=0x%x\n", MMR (TLMM_B + 0x5F000));

  {
    // PMK8550 (sid 0) GPIO3 = "alt_sleep_clk" func1 output = the 32 kHz sleep clock the WCN7850 needs (DT pmk8550 pinctrl alt_sleep_clk_default)
    UINT8  R[8];
    UINT32 K;
    STATIC CONST UINT16  Regs[] = { 0x05, 0x08, 0x40, 0x41, 0x42, 0x44, 0x45, 0x46 };

    for (K = 0; K < sizeof (Regs) / sizeof (Regs[0]); K++) {
      if (SpmiReadBytes (0, 0xBA00 + Regs[K], 1, R)) {
        PL ("pmk8550 gpio3 reg 0x%02x = 0x%02x\n", Regs[K], R[0]);
      } else {
        PL ("pmk8550 gpio3 reg 0x%02x: read failed (apid not owned by EE0?)\n", Regs[K]);
      }
    }
    // gpio_lv_mv: MODE_CTL(0x40) = dir out(1)<<4 | func1(2)<<1 | value 0 ; VIN 0x41=0 (power-source 0) ; PULL 0x42=5 (disable) ; EN_CTL(0x46)=0x80
    // LV/MV subtype (mainline pinctrl-spmi-gpio.c): MODE_CTL bits[1:0] = dir (1 = output), function lives in LV_MV_DIG_OUT_SOURCE_CTL (0x44) = func index (FUNC1 = 2)
    PL ("pmk8550 gpio3 program: %d %d %d %d %d\n", SpmiWriteByte (0, 0xBA40, 0x01), SpmiWriteByte (0, 0xBA41, 0x00),
        SpmiWriteByte (0, 0xBA42, 0x05), SpmiWriteByte (0, 0xBA44, 0x02), SpmiWriteByte (0, 0xBA46, 0x80));
    PL ("pmk8550 gpio3 out-strength (0x45) -> 3 (high, as Android): %d\n", SpmiWriteByte (0, 0xBA45, 0x03));
    PcDelayMs (5);
    PL ("pmk8550 gpio3 en immediately: 0x%02x\n", SpmiReadBytes (0, 0xBA46, 1, R) ? R[0] : 0xEE);
    for (K = 0; K < sizeof (Regs) / sizeof (Regs[0]); K++) {
      if (SpmiReadBytes (0, 0xBA00 + Regs[K], 1, R)) {
        PL ("pmk8550 gpio3 reg 0x%02x now 0x%02x\n", Regs[K], R[0]);
      }
    }
  }
  // 1. PERST asserted (output low), clkreq to pcie0_clk_req_n, wake input
#define PC_ANDROID_PINORDER 1
#if PC_ANDROID_PINORDER
  // Android's power-off state (trace 2026-10-21): PERST# driven HIGH while WLAN_EN is low; CLKREQ/WAKE as plain GPIO with pull-up
  PcGpio (94, 0x201, 1);
  PcGpio (95, 3, -1);
  PcGpio (96, 3, -1);
#else
  PcGpio (94, 0x201, 0);
  PcGpio (95, (1 << 2) | 3, -1);
  PcGpio (96, 3, -1);
#endif

  // 1b. AOP wlan_pdc configuration, exactly the messages Android sends before the WCN7850 power-on (pdc_init_table + cnss_aop_set_vreg_param)
  if (QmpOpen ()) {
    STATIC CONST CHAR8  *Msgs[] = {
      "{class: wlan_pdc, ss: rf, res: s3c.v, upval: 916}",  "{class: wlan_pdc, ss: rf, res: s3c.v, dwnval: 612}",
      "{class: wlan_pdc, ss: rf, res: s1c.v, upval: 1316}", "{class: wlan_pdc, ss: rf, res: s1c.v, dwnval: 944}",
      "{class: wlan_pdc, ss: rf, res: s6c.v, upval: 1864}", "{class: wlan_pdc, ss: rf, res: s6c.v, dwnval: 1820}",
      "{class: wlan_pdc, ss: rf, res: s3c.v, upval: 916}",  "{class: wlan_pdc, ss: rf, res: s3c.v, dwnval: 612}",
      "{class: wlan_pdc, ss: rf, res: s1c.v, upval: 1316}", "{class: wlan_pdc, ss: rf, res: s1c.v, dwnval: 944}",
      "{class: wlan_pdc, ss: rf, res: s6c.v, upval: 1864}", "{class: wlan_pdc, ss: rf, res: s6c.v, dwnval: 1820}",
      "{class: wlan_pdc, ss: bb, res: s2c.v, upval: 976}",  "{class: wlan_pdc, ss: bb, res: s2c.v, dwnval: 512}",
      "{class: wlan_pdc, ss: bb, res: s4i.v, upval: 940}",  "{class: wlan_pdc, ss: bb, res: s4i.v, dwnval: 420}",
    };
    UINT32  K, Ok = 0;

    for (K = 0; K < sizeof (Msgs) / sizeof (Msgs[0]); K++) {
      Ok += QmpSend (Msgs[K]) ? 1 : 0;
    }
    PL ("qmp wlan_pdc: %u/%u accepted\n", Ok, (UINT32)(sizeof (Msgs) / sizeof (Msgs[0])));
  }
  PL ("sw_ctrl before power: gpio18 cfg=0x%x io=0x%x gpio19 cfg=0x%x io=0x%x\n", MMR (TLMM_B + 0x12000), MMR (TLMM_B + 0x12004),
      MMR (TLMM_B + 0x13000), MMR (TLMM_B + 0x13004));

  // 1c. 2026-10-21: Android (cold-boot trace, 1.662 s, just before WLAN_EN) sets TLMM INTR_CFG (+0x008) = 0x7c2 on gpio18 and gpio19 (sw_ctrl, mpm_wake_set_gpios <0x12 0x13>)
  //     and on gpio96 (WAKE) at 1.391 s: this routes the WCN's SW_CTRL pins into the MPM/PDC so that AOP's wlan_pdc moves the WCN rails to their 'up' values.
  MMW (TLMM_B + 0x1000ULL * 18 + 8, 0x7C2);
  MMW (TLMM_B + 0x1000ULL * 19 + 8, 0x7C2);
  MMW (TLMM_B + 0x1000ULL * 96 + 8, 0x7C2);
  PL ("tlmm intr_cfg: g18=0x%x g19=0x%x g96=0x%x\n", MMR (TLMM_B + 0x1000ULL * 18 + 8), MMR (TLMM_B + 0x1000ULL * 19 + 8), MMR (TLMM_B + 0x1000ULL * 96 + 8));

  // 2b. PCIe CESTA (2026-10-16 boot trace, winboot/boottrace2): on SM8650 the PCIe0 clocks/GDSC/rails are sequenced in hardware by
  //     pcie_sm (0x1d07000) + the PCIe CRM (0x1d01000); the DT pcie0 node has a single clock and no rail supplies.
  //     Android order: crm_probe (0.39 s) -> pcie_sm program (1.39 s: debug 0x1040/0x1048 <- 0, seq @+0, branch @+0x1000, start +0x1090 <- 1)
  //     -> CRM power-state tables (1.67 s, two channel switches via +0x1020) -> PARF/PHY (1.673 s) -> link up 1.703 s.
  {
    STATIC CONST UINT32  SmSeq[13]   = { 0x1c018081, 0x70074002, 0x50028000, 0x28007003, 0x80804002, 0x70021c01, 0x18001802,
                                         0x70005000, 0x10004000, 0x80814002, 0x18001c01, 0x1c018080, 0x100 };
    STATIC CONST UINT32  SmBranch[7] = { 0x04, 0x1c, 0x24, 0x2c, 0, 0, 0 };
    CONST UINT64         Sm = 0x1D07000ULL;
    UINT32               K;

    PcEnsureMmio (0x1D01000ULL, 0x6000, "PCIE_CRM");
    PcEnsureMmio (Sm, 0x7000, "PCIE_SM");
    PL ("crm pre: ver=0x%08x chn_sts(+0x1000)=0x%08x chn(+0x1020)=0x%08x 0x11e0=0x%x 0x1580=0x%x\n", MMR (0x1D01000ULL), MMR (0x1D02000ULL),
        MMR (0x1D02020ULL), MMR (0x1D021E0ULL), MMR (0x1D02580ULL));
    PL ("sm pre: 0x0=0x%08x 0x1000=0x%x 0x1040=0x%x 0x1048=0x%x 0x1050=0x%x 0x1090=0x%x 0x1094=0x%x 0x1098=0x%x 0x109c=0x%x\n", MMR (Sm),
        MMR (Sm + 0x1000), MMR (Sm + 0x1040), MMR (Sm + 0x1048), MMR (Sm + 0x1050), MMR (Sm + 0x1090), MMR (Sm + 0x1094), MMR (Sm + 0x1098),
        MMR (Sm + 0x109C));
    for (K = 0; K < sizeof (mPcieCrmProbe) / sizeof (mPcieCrmProbe[0]); K++) {
      MMW (mPcieCrmProbe[K][0], mPcieCrmProbe[K][1]);
    }
    MMW (Sm + 0x1040, 0);
    MMW (Sm + 0x1048, 0);
    for (K = 0; K < 13; K++) {
      MMW (Sm + 4 * K, SmSeq[K]);
    }
    for (K = 0; K < 7; K++) {
      MMW (Sm + 0x1000 + 4 * K, SmBranch[K]);
    }
    MMW (Sm + 0x1090, 1);
    PcDelayMs (1);
    PL ("sm programmed: 0x0=0x%08x 0x30=0x%x 0x1000=0x%x 0x1040=0x%x 0x1048=0x%x 0x1050=0x%x 0x1090=0x%x 0x1094=0x%x 0x1098=0x%x 0x109c=0x%x\n",
        MMR (Sm), MMR (Sm + 0x30), MMR (Sm + 0x1000), MMR (Sm + 0x1040), MMR (Sm + 0x1048), MMR (Sm + 0x1050), MMR (Sm + 0x1090),
        MMR (Sm + 0x1094), MMR (Sm + 0x1098), MMR (Sm + 0x109C));
  }

  // 2. rails: PCIe PHY supplies first, then the WCN7850 supplies, then WLAN_EN
#define PC_NO_EXTRA_VOTES 1
#if !PC_NO_EXTRA_VOTES
  PcRail ("ldoe3", 912000);
#endif
  PcRailMode ("ldoi3", 1200000, 7);
  PcRailMode ("ldoi1", 880000, 7);
  PcRail ("smpc3", 916000);
  PcRail ("smpc2", 976000);
  PcRail ("smpi4", 940000);
  PcRailMode ("ldoc3", 1200000, 3);
  PcRailHpm ("ldob15", 1800000);
  PcRailHpm ("ldok6", 1800000);                          // missing until 2026-10-16: cnss enables it (1.8 V, HPM) right after ldob15
  PcRailMode ("smpc1", 1315000, 7);
  PcRail ("smpc6", 1863000);
  {
    UINT32  Ck = CmdDbAddr ("clka1");                       // RPMH_RF_CLK1: the WCN7850 PMU reference clock (sm8650-qrd wcn7850-pmu clocks)

    PL ("rf_clk1 (clka1) addr=0x%x\n", Ck);
    if (Ck != 0) {
#if !PC_NO_EXTRA_VOTES
      RpmhWrite (Ck, 1);
#endif
    }
  }
#define PC_RAIL_SETTLE_MS 300
  PcDelayMs (PC_RAIL_SETTLE_MS);                         // Android: the WCN rails are up long before WLAN_EN (rails stable for >> 100 ms)
  mPcQuiet = TRUE;
  TWlan = PcNowUs ();
#define PC_BT_EN_FIRST 1
#if PC_BT_EN_FIRST
  PcGpio (17, (7 << 6) | 3 | (1 << 9), 1);               // Android keeps BT_EN (gpio17) high all the time; WLAN_EN rises with the PMU already up
  gBS->Stall (2000);
#endif
  PcGpio (16, (7 << 6) | 3 | (1 << 9), 1);               // WLAN_EN high, 16 mA, pull-up
#if PC_ANDROID_PINORDER
  gBS->Stall (1500);                                      // Android: PERST/CLKREQ/WAKE are configured ~1.5 ms after WLAN_EN
  PcGpio (95, (1 << 2) | 3, -1);
  PcGpio (96, 3, -1);
  PcGpio (94, 0x201, 0);
#endif
  PL ("rails+WLAN_EN done\n");
  {
    CONST UINT64  Sm = 0x1D07000ULL;
    UINT32        K;

    for (K = 0; K < sizeof (mPcieCrmPwr) / sizeof (mPcieCrmPwr[0]); K++) {
      MMW (mPcieCrmPwr[K][0], mPcieCrmPwr[K][1]);
      if (mPcieCrmPwr[K][0] == 0x1D02020) {
        UINT32  W, S0 = MMR (0x1D02000ULL), S1 = S0;

        for (W = 0; W < 100 && S1 == S0; W++) {
          gBS->Stall (100);
          S1 = MMR (0x1D02000ULL);
        }
        PL ("crm channel switch -> %u: chn_sts 0x%08x -> 0x%08x after %u x100us, chn=0x%08x\n", mPcieCrmPwr[K][1], S0, S1, W, MMR (0x1D02020ULL));
      }
    }
    TCrm = PcNowUs ();
    PL ("sm after crm: 0x1040=0x%x 0x1048=0x%x 0x1050=0x%x 0x1058=0x%x 0x1060=0x%x 0x1068=0x%x 0x1070=0x%x 0x1078=0x%x 0x1080=0x%x 0x1088=0x%x 0x1090=0x%x 0x1094=0x%x 0x1098=0x%x 0x109c=0x%x\n",
        MMR (Sm + 0x1040), MMR (Sm + 0x1048), MMR (Sm + 0x1050), MMR (Sm + 0x1058), MMR (Sm + 0x1060), MMR (Sm + 0x1068), MMR (Sm + 0x1070),
        MMR (Sm + 0x1078), MMR (Sm + 0x1080), MMR (Sm + 0x1088), MMR (Sm + 0x1090), MMR (Sm + 0x1094), MMR (Sm + 0x1098), MMR (Sm + 0x109C));
    PL ("gcc after crm: pcie_0_gdsc=0x%08x phy_gdsc=0x%08x vote_en=0x%08x/0x%08x tcsr_clkref=0x%08x\n", MMR (GCC_B + 0x6B004),
        MMR (GCC_B + 0x6C000), MMR (GCC_B + 0x52008), MMR (GCC_B + 0x52000), MMR (TCSR_CLKREF));
  }

  // 3. reference clock + GCC
  MMW (TCSR_CLKREF, MMR (TCSR_CLKREF) | 1);
  PL ("tcsr clkref=0x%08x\n", MMR (TCSR_CLKREF));
#define PC_ANDROID_GDSC 1
#if PC_ANDROID_GDSC
  // 2026-10-21 Android keeps the pcie_0_gdsc SW collapse vote (GCC+0x5214C bit 0 stays 1: 0x17) and only drops the PHY one (bit 3); the core GDSC is CESTA-managed
  PL ("gdsc core before: gdscr=0x%08x vote=0x%08x phy gdscr=0x%08x\n", MMR (GCC_B + 0x6B004), MMR (GCC_B + 0x5214C), MMR (GCC_B + 0x6C000));
  PcGdsc (0x6C000, 1U << 3, "pcie_0_phy_gdsc");
  PL ("gdsc core after: gdscr=0x%08x vote=0x%08x phy gdscr=0x%08x\n", MMR (GCC_B + 0x6B004), MMR (GCC_B + 0x5214C), MMR (GCC_B + 0x6C000));
#else
  MMW (GCC_B + 0x52150, 0);
  PcGdsc (0x6B004, 1U << 0, "pcie_0_gdsc");
  PcGdsc (0x6C000, 1U << 3, "pcie_0_phy_gdsc");
#endif
  PcRcgUpdate (0x6B074, 0, "aux(xo)");
#define PC_RCHNG_ANDROID 1
#if PC_RCHNG_ANDROID
  // Android gcc probe (boot trace 0.570 s): phy_rchng RCG = XO div1 (cfg 0x100001); root enable is released again afterwards (branch is hardware gated)
  MMW (GCC_B + 0x6B058, 2);
  MMW (GCC_B + 0x6B05C, 0x100001);
  MMW (GCC_B + 0x6B058, 0x13);
  PcPoll (GCC_B + 0x6B058, 1, 0, 2000);
  MMW (GCC_B + 0x6B058, 0);
#else
  PcRcgUpdate (0x6B058, (6U << 8) | 5, "rchng(gpll0_even/3)");
#endif
  MMW (GCC_B + 0x52008, MMR (GCC_B + 0x52008) | 0x6F);   // slv_axi mstr_axi cfg_ahb aux slv_q2a cnoc_sf (pipe later)
  MMW (GCC_B + 0x52000, MMR (GCC_B + 0x52000) | (1U << 12) | (1U << 19) | (1U << 22));
  PcDelayMs (1);
  PcClkHalt (0x6B020, "slv_axi");
  PcClkHalt (0x6B02C, "mstr_axi");
  PcClkHalt (0x6B038, "cfg_ahb");
  PcClkHalt (0x6B03C, "aux");
  PcClkHalt (0x6B01C, "slv_q2a");
  PcClkHalt (0x10058, "cnoc_pcie_sf_axi");
  PcClkHalt (0x10064, "aggre_noc_pcie_axi");
  PcClkHalt (0x10074, "ddrss_pcie_sf_qtb");
  PcClkHalt (0x6B054, "phy_rchng");

  { UINT32 Pass;
  for (Pass = 0; Pass < 2; Pass++) {
    if (Pass) {   // second full pass without any power cycle: does a dirty PHY/controller change anything?
      MMW (TLMM_B + 0x1000ULL * 94 + 4, 0);
      MMW (PARF_B + 0x1B0, 0);
      PcDelayMs (100);
      PL ("=== second pass\n");
    }
  // 4. core + link-down BCR pulse (Linux: assert, 1 ms, deassert, 1 ms)
  MMW (GCC_B + 0x6B000, 1);
  MMW (GCC_B + 0x6C014, 1);
  PcDelayMs (1);
  MMW (GCC_B + 0x6B000, 0);
  MMW (GCC_B + 0x6C014, 0);
  PcDelayMs (1);

  { UINT32 Qo; for (Qo = 0; Qo < 0x700; Qo += 4) { mRstP[Qo / 4] = MMR (PARF_B + Qo); } }
  // (DBI is not readable before the PHY pipe clock runs: reading it here hangs the SoC in Mu)
  // 5. PARF (qcom_pcie_init_2_7_0)
  PL ("parf sys_ctrl=0x%08x phy_ctrl=0x%08x pm_ctrl=0x%08x devtype=0x%x ltssm=0x%08x\n", MMR (PARF_B + 0x0), MMR (PARF_B + 0x40),
      MMR (PARF_B + 0x20), MMR (PARF_B + 0x1000), MMR (PARF_B + 0x1B0));
  // exact values/order of the Android pci-msm driver (ftrace rwmmio capture of msm_pcie_enable_link, winboot\android_enable_seq.txt)
  MMW (PARF_B + 0x1000, 4);                                         // RC
  MMW (PARF_B + 0x20, 0);                                           // PM_CTRL
  MMW (PARF_B + 0x40, 0x900);                                       // PHY_CTRL
  MMW (PARF_B + 0x350, 0);                                          // DBI_BASE_V2 stays 0 on this SoC
  MMW (PARF_B + 0x0, 0x365E);                                       // SYS_CTRL
  MMW (PARF_B + 0x174, 0x13);                                       // MHI_CLOCK_RESET_CTRL
  MMW (PARF_B + 0x22C, 0);                                          // INT_ALL_MASK
  MMW (PARF_B + 0x22C, 0x7F80D202);
  MMW (PARF_B + 0x358, 0x4000000);                                  // SLV_ADDR_SPACE_SIZE (64 MB)
  MMW (PARF_B + 0x1A8, 0x80000014);                                 // AXI_MSTR_WR_ADDR_HALT_V2
  PL ("parf done: devtype=0x%x phy_ctrl=0x%08x dbi=0x%x/0x%x atu=0x%x\n", MMR (PARF_B + 0x1000), MMR (PARF_B + 0x40),
      MMR (PARF_B + 0x350), MMR (PARF_B + 0x354), MMR (PARF_B + 0x634));

  // 6. PHY: BCR pulse (NOCSR stays asserted while the tables are written), DT phy-sequence, pipe clock, release, wait for ready
  PL ("phy pre: status(0x214)=0x%x pwrdn(0x240)=0x%x\n", MMR (PHY_B + 0x214), MMR (PHY_B + 0x240));
  MMW (GCC_B + 0x6C01C, 1);
  PcDelayMs (1);
  MMW (GCC_B + 0x6C01C, 0);
  PcDelayMs (1);
  { UINT32 Qo; for (Qo = 0; Qo < 0x1400; Qo += 4) { mRstH[Qo / 4] = MMR (PHY_B + Qo); } }
  MMW (GCC_B + 0x6B070, 0);                                         // pipe mux -> PHY pipe clock (Android keeps it on across the cycle)
  MMW (GCC_B + 0x52008, MMR (GCC_B + 0x52008) | (1U << 4));         // pipe clk vote
  for (I = 0; I < N; I++) {
    MMW (PHY_B + mPciePhySeq[I][0], mPciePhySeq[I][1]);
    if (mPciePhySeq[I][2]) {
      gBS->Stall (mPciePhySeq[I][2]);
    }
  }
  PL ("phy seq written; pwrdn(0x240)=0x%x 0x244=0x%x\n", MMR (PHY_B + 0x240), MMR (PHY_B + 0x244));
  V = PcPoll (PHY_B + 0x214, 1U << 6, 0, 200000);
  TPhy = PcNowUs ();
  PL ("phy ready=%d status(0x214)=0x%x pipe mux=0x%x\n", V, MMR (PHY_B + 0x214), MMR (GCC_B + 0x6B070));

  // 7. post-PHY controller setup + PERST release + LTSSM enable, same order as Android (DBI port-logic / EQ settings between PERST and LTSSM)
  PcDelayMs (10);                                                   // Android: PERST released ~12 ms after PHY ready
  MMW (PARF_B + 0x2C4, 0x68);
  MMW (PARF_B + 0x2C4, 0x168);
  MMW (DBI_B + 0x714, 0x8000020);
  MMW (TLMM_B + 0x1000ULL * 94 + 4, 2);                             // PERST released
  TPerst = PcNowUs ();
  mPcQuiet = FALSE;
  PL ("timing us: WLAN_EN->crm_done %lu, WLAN_EN->phy_ready %lu, phy_ready->PERST %lu, WLAN_EN->PERST %lu (Android: 19000 / ~7000 / ~12000)\n", TCrm - TWlan, TPhy - TWlan, TPerst - TPhy, TPerst - TWlan);
  PL ("PERST released, gpio94 io=0x%x\n", MMR (TLMM_B + 0x1000ULL * 94 + 4));
  PcDelayMs (1);
  PL ("dbi pre: 0x708=0x%08x 0x70c=0x%08x 0x710=0x%08x 0x714=0x%08x 0x80c=0x%08x 0x818=0x%08x\n", MMR (DBI_B + 0x708), MMR (DBI_B + 0x70C),
      MMR (DBI_B + 0x710), MMR (DBI_B + 0x714), MMR (DBI_B + 0x80C), MMR (DBI_B + 0x818));
  MMW (DBI_B + 0x8BC, MMR (DBI_B + 0x8BC) | 1);                     // DBI_RO_WR_EN
  // 2026-10-21: Android never writes PORT_LINK_CTRL (0x710); LNKCAP 0x7c reads x2 and the link comes up x2 (WCN7850 is x2) -> leave LINK_CAPABLE at the hardware default (x2)
  PL ("dbi 0x710 -> 0x%08x\n", MMR (DBI_B + 0x710));
  MMW (DBI_B + 0x80C, 0x130190);
  MMW (DBI_B + 0x890, 0x2001);
  MMW (DBI_B + 0x8A8, 0xC000060);
  MMW (DBI_B + 0x890, 0x2000);
  MMW (DBI_B + 0x8AC, 0x155A0);
  MMW (DBI_B + 0x8BC, 0x5BF41);
  MMW (DBI_B + 0x154, 0x55555555);
  MMW (DBI_B + 0x8BC, 0x5BF40);
  MMW (DBI_B + 0xA0, 0x10041);
  MMW (DBI_B + 0x78, 0x105810);
  { UINT32 Qo; for (Qo = 0; Qo < 0x700; Qo += 4) { mBfP[Qo / 4] = MMR (PARF_B + Qo); } for (Qo = 0; Qo < 0x900; Qo += 4) { mBfD[Qo / 4] = MMR (DBI_B + Qo); } for (Qo = 0; Qo < 0x1400; Qo += 4) { mBfH[Qo / 4] = MMR (PHY_B + Qo); } }
  MMW (PARF_B + 0x1B0, 0x100);                                      // LTSSM enable
  for (I = 0; I < 3; I++) {
    PcDelayMs (100);
    V = MMR (DBI_B + 0x72C);
    PL ("t=%u ms: ltssm=0x%08x dbg1=0x%08x linkup=%d parf_status=0x%x\n", (I + 1) * 100, MMR (PARF_B + 0x1B0), V,
        (V & 0x10) && !(V & (1U << 29)), MMR (PARF_B + 0x230));
    if ((V & 0x10) && !(V & (1U << 29))) {
      break;
    }
  }

    if (((MMR (DBI_B + 0x72C)) & 0x10) && !(MMR (DBI_B + 0x72C) & (1U << 29))) { break; }
  }
  }
  {
    // which PMIC regulators are readable by EE0 and what state are they in? (STATUS1 @+0x08 bit7 = VREG_OK, EN_CTL @+0x46 bit7)
    STATIC CONST UINT8   Sids[] = { 1, 2, 3, 4, 6, 7, 8, 0xA };
    UINT32               Si, Bi, Seen = 0;
    UINT8                S1[2], En[2];

    for (Si = 0; Si < sizeof (Sids); Si++) {
      for (Bi = 0; Bi < 6 + 16; Bi++) {
        UINT32  Base = (Bi < 6) ? (0x1400 + 0x300 * Bi) : (0x4000 + 0x100 * (Bi - 6));

        if (SpmiReadBytes (Sids[Si], Base + 0x08, 1, S1) && SpmiReadBytes (Sids[Si], Base + 0x46, 1, En)) {
          PL ("pmic sid%u 0x%04x: status1=0x%02x en=0x%02x\n", Sids[Si], Base, S1[0], En[0]);
          Seen++;
        }
      }
    }
    PL ("pmic regulators readable by EE0: %u\n", Seen);
  }

  // retrain experiments: toggle LTSSM_EN / PERST and log every LTSSM state change (20 us resolution)
  PcEnsureMmio (0x1D07000ULL, 0x7000, "PCIE_SM");
  V = MMR (DBI_B + 0x72C);
  if ((V & 0x10) && !(V & (1U << 29))) {
    PL ("LINK IS UP (dbg1=0x%08x) - skipping the retrain experiments, waiting 100 ms before config access\n", V);
    PcDelayMs (100);
  } else
  for (I = 0; I < 4; I++) {
    UINT32  Last = 0xFFFFFFFF, Cur, Us, Logged = 0;

    MMW (PARF_B + 0x1B0, MMR (PARF_B + 0x1B0) & ~(1U << 8));
    if (I >= 1) {
      MMW (TLMM_B + 0x1000ULL * 94 + 4, 0);                             // PERST low
      if (I == 1) {
        // variant 1 (2026-10-16): read-only pcie_sm / CRM state (the old variant wrote the seq at +0x1090 = wrong; now programmed in step 2b)
        PL ("retrain1 sm: 0x1040=0x%x 0x1048=0x%x 0x1050=0x%x 0x1090=0x%x 0x1094=0x%x 0x1098=0x%x 0x109c=0x%x crm chn_sts=0x%08x chn=0x%08x\n",
            MMR (0x1D07000ULL + 0x1040), MMR (0x1D07000ULL + 0x1048), MMR (0x1D07000ULL + 0x1050), MMR (0x1D07000ULL + 0x1090),
            MMR (0x1D07000ULL + 0x1094), MMR (0x1D07000ULL + 0x1098), MMR (0x1D07000ULL + 0x109C), MMR (0x1D02000ULL), MMR (0x1D02020ULL));
      } else if (I == 2) {
        PcGpio (17, (7 << 6) | 3 | (1 << 9), 1);                        // variant 2: BT_EN high too
      } else if (I == 3) {
        MMW (TLMM_B + 0x1000ULL * 16 + 4, 0);                           // variant 3: power-cycle the endpoint (WLAN_EN)
        PcDelayMs (100);
        MMW (TLMM_B + 0x1000ULL * 16 + 4, 2);
        PcDelayMs (150);
      }
      PcDelayMs (100);
      MMW (TLMM_B + 0x1000ULL * 94 + 4, 2);
      PcDelayMs (20);
    }
    PL ("retrain %u: clkreq(g95)=%u wake(g96)=%u\n", I, MMR (TLMM_B + 0x5F004) & 1, MMR (TLMM_B + 0x60004) & 1);
    MMW (PARF_B + 0x1B0, MMR (PARF_B + 0x1B0) | (1U << 8));
    for (Us = 0; Us < 300000 && Logged < 40; Us += 20) {
      Cur = MMR (PARF_B + 0x1B0) & 0x3F;
      if (Cur != Last) {
        PL ("retrain %u: +%u us ltssm=0x%02x dbg0=0x%08x dbg1=0x%08x\n", I, Us, Cur, MMR (DBI_B + 0x728), MMR (DBI_B + 0x72C));
        Last = Cur;
        Logged++;
      }
      gBS->Stall (20);
    }
    V = MMR (DBI_B + 0x72C);
    if ((V & 0x10) && !(V & (1U << 29))) {
      PL ("retrain %u: LINK UP dbg1=0x%08x\n", I, V);
      break;
    }
  }
  if (mPcKeep) {
    mPcQuiet = TRUE;
  }
  PL ("diag: pipe clk halt(0x6b048)=0x%08x vote=0x%08x clkreq(g95) io=0x%x wake(g96) io=0x%x wlan_en(g16) io=0x%x\n", MMR (GCC_B + 0x6B048),
      MMR (GCC_B + 0x52008), MMR (TLMM_B + 0x5F004), MMR (TLMM_B + 0x60004), MMR (TLMM_B + 0x10004));
  PL ("diag: dbi 0x728=0x%08x 0x72c=0x%08x 0x730=0x%08x 0x734=0x%08x 0x738=0x%08x 0x73c=0x%08x\n", MMR (DBI_B + 0x728), MMR (DBI_B + 0x72C),
      MMR (DBI_B + 0x730), MMR (DBI_B + 0x734), MMR (DBI_B + 0x738), MMR (DBI_B + 0x73C));
  PL ("diag: parf 0x1b0=0x%08x 0x24=0x%08x 0x28=0x%08x 0x224=0x%08x 0x230=0x%08x 0x500=0x%08x 0x4d0=0x%08x 0x4d4=0x%08x 0x3c0=0x%08x 0x630=0x%08x\n",
      MMR (PARF_B + 0x1B0), MMR (PARF_B + 0x24), MMR (PARF_B + 0x28), MMR (PARF_B + 0x224), MMR (PARF_B + 0x230), MMR (PARF_B + 0x500),
      MMR (PARF_B + 0x4D0), MMR (PARF_B + 0x4D4), MMR (PARF_B + 0x3C0), MMR (PARF_B + 0x630));
  PL ("diag: phy 0x214=0x%08x 0x218=0x%08x 0x21c=0x%08x 0x220=0x%08x 0x224=0x%08x 0x228=0x%08x 0x22c=0x%08x 0x230=0x%08x 0x234=0x%08x\n",
      MMR (PHY_B + 0x214), MMR (PHY_B + 0x218), MMR (PHY_B + 0x21C), MMR (PHY_B + 0x220), MMR (PHY_B + 0x224), MMR (PHY_B + 0x228),
      MMR (PHY_B + 0x22C), MMR (PHY_B + 0x230), MMR (PHY_B + 0x234));
  PL ("diag: phy dbg 0x1cc=0x%x 0x1d0=0x%x 0x1d4=0x%x 0x1d8=0x%x 0x1dc=0x%x 0x1e0=0x%x 0x1e4=0x%x 0x1f8=0x%x 0xa00=0x%x 0x1200=0x%x 0xa04=0x%x 0x1204=0x%x\n",
      MMR (PHY_B + 0x1CC), MMR (PHY_B + 0x1D0), MMR (PHY_B + 0x1D4), MMR (PHY_B + 0x1D8), MMR (PHY_B + 0x1DC), MMR (PHY_B + 0x1E0),
      MMR (PHY_B + 0x1E4), MMR (PHY_B + 0x1F8), MMR (PHY_B + 0xA00), MMR (PHY_B + 0x1200), MMR (PHY_B + 0xA04), MMR (PHY_B + 0x1204));
  {
    // 2026-10-21: same GCC window as refs/android_gccdump.sh (Android, link up + ping load) for a state diff
    UINT32  O, Col = 0;
    for (O = 0x10050; O < 0x10084; O += 4) { PL ("GCCD %05x %08x\n", O, MMR (GCC_B + O)); }
    for (O = 0x52000; O < 0x52180; O += 4) { PL ("GCCD %05x %08x\n", O, MMR (GCC_B + O)); }
    PL ("GCCD 5214c %08x\n", MMR (GCC_B + 0x5214C)); PL ("GCCD 52150 %08x\n", MMR (GCC_B + 0x52150));
    for (O = 0x6B000; O < 0x6B0A4; O += 4) { PL ("GCCD %05x %08x\n", O, MMR (GCC_B + O)); }
    for (O = 0x6C000; O < 0x6C044; O += 4) { PL ("GCCD %05x %08x\n", O, MMR (GCC_B + O)); }
    PL ("GCCD tcsr_clkref %08x\n", MMR (TCSR_CLKREF));
    { UINT32 Qo; for (Qo = 0; Qo < 0x700; Qo += 4) { if (mBfP[Qo / 4]) { PL ("BPARF %04x %08x\n", Qo, mBfP[Qo / 4]); } }
      for (Qo = 0; Qo < 0x900; Qo += 4) { if (mBfD[Qo / 4]) { PL ("BDBI %04x %08x\n", Qo, mBfD[Qo / 4]); } }
      for (Qo = 0; Qo < 0x1400; Qo += 4) { if (mBfH[Qo / 4]) { PL ("BPHY %04x %08x\n", Qo, mBfH[Qo / 4]); } } }
    { UINT32 Qo; for (Qo = 0; Qo < 0x700; Qo += 4) { if (mRstP[Qo / 4]) { PL ("RPARF %04x %08x\n", Qo, mRstP[Qo / 4]); } }
      for (Qo = 0; Qo < 0x900; Qo += 4) { if (mRstD[Qo / 4]) { PL ("RDBI %04x %08x\n", Qo, mRstD[Qo / 4]); } }
      for (Qo = 0; Qo < 0x1400; Qo += 4) { if (mRstH[Qo / 4]) { PL ("RPHY %04x %08x\n", Qo, mRstH[Qo / 4]); } } }
    {
      // same ranges as the Android /dev/mem dump (winboot/wifitrace/android_devmem2.txt); only non-zero words are logged
      STATIC CONST UINT64  Rg[][2] = { { 0x1D01000ULL, 1024 }, { 0x1D02000ULL, 1024 }, { 0x1C00000ULL, 448 }, { 0x1C06000ULL, 1280 } };
      UINT32               Ri, Wi, Vv;
      for (Ri = 0; Ri < 4; Ri++) {
        for (Wi = 0; Wi < Rg[Ri][1]; Wi++) {
          Vv = MMR (Rg[Ri][0] + 4ULL * Wi);
          if (Vv != 0) { PL ("DMPW %08lx %08x\n", (UINT64)(Rg[Ri][0] + 4ULL * Wi), Vv); }
        }
      }
    }
    (VOID)Col;
  }
  mPcQuiet = FALSE;
  // 8. root port + endpoint config space
  PL ("RC cfg: id=0x%08x cmd/sts=0x%08x class=0x%08x hdr=0x%08x\n", MMR (DBI_B + 0), MMR (DBI_B + 4), MMR (DBI_B + 8), MMR (DBI_B + 0xC));
  {
    UINT32 Cap = MMR (DBI_B + 0x34) & 0xFF;
    UINT32 Guard = 0;
    while (Cap && Guard++ < 16) {
      UINT32 H = MMR (DBI_B + Cap);
      if ((H & 0xFF) == 0x10) {
        PL ("RC pcie cap at 0x%x: lnkcap=0x%08x lnkctl/sta=0x%08x\n", Cap, MMR (DBI_B + Cap + 0xC), MMR (DBI_B + Cap + 0x10));
        break;
      }
      Cap = (H >> 8) & 0xFF;
    }
  }
  MMW (DBI_B + 0x18, 0x00010100);                                   // pri 0, sec 1, sub 1
  MMW (DBI_B + 0x04, MMR (DBI_B + 0x04) | 6);                       // mem + bus master
  MMW (ATU_B + 0x00, 4);                                            // outbound region 0: CFG0
  MMW (ATU_B + 0x08, (UINT32)CFG_B);
  MMW (ATU_B + 0x0C, 0);
  MMW (ATU_B + 0x10, (UINT32)CFG_B + 0xFFFFF);
  MMW (ATU_B + 0x14, 0x01000000);                                   // bus 1 dev 0 fn 0
  MMW (ATU_B + 0x18, 0);
  MMW (ATU_B + 0x04, 0x80000000);
  PL ("atu ctrl2=0x%08x\n", MMR (ATU_B + 0x04));
  PL ("sw_ctrl at end: gpio18 io=0x%x gpio19 io=0x%x\n", MMR (TLMM_B + 0x12004), MMR (TLMM_B + 0x13004));
  PL ("EP cfg: id=0x%08x cmd/sts=0x%08x class=0x%08x hdr=0x%08x bar0=0x%08x  (expect id 0x110717cb)\n", MMR (CFG_B + 0), MMR (CFG_B + 4), MMR (CFG_B + 8),
      MMR (CFG_B + 0xC), MMR (CFG_B + 0x10));

  // 2026-10-21 ECAM experiment: DW iATU CFG shift mode, so that ECAM-style addresses (dev<<15 | fn<<12) reach other devfns of bus 1
  // dev 0 only (32 KB = 8 functions) goes to the EP in shift mode; everything else of bus 1 is sent as a Type 1 request to a bus the EP can not route -> UR -> 0xFFFFFFFF
  MMW (ATU_B + 0x10, (UINT32)CFG_B + 0x7FFF);
  MMW (ATU_B + 0x200 + 0x00, 5);                                    // region 1: CFG1 (Type 1)
  MMW (ATU_B + 0x200 + 0x08, (UINT32)CFG_B + 0x8000);
  MMW (ATU_B + 0x200 + 0x0C, 0);
  MMW (ATU_B + 0x200 + 0x10, (UINT32)CFG_B + 0xFFFFF);
  MMW (ATU_B + 0x200 + 0x14, 0x7F000000);                           // bus 0x7f dev 0 fn 0 : not behind the link
  MMW (ATU_B + 0x200 + 0x18, 0);
  MMW (ATU_B + 0x200 + 0x04, 0x80000000);
  MMW (ATU_B + 0x04, 0x90000000);                                   // enable | CFG_SHIFT_MODE (bit 28)
  PL ("ECAM shift: atu ctrl2=0x%08x\n", MMR (ATU_B + 0x04));
  PL ("ECAM shift: d0f0 id=0x%08x", MMR (CFG_B + 0x0000));
  PL (" d0f1 id=0x%08x", MMR (CFG_B + 0x1000));
  PL (" d1f0 id=0x%08x", MMR (CFG_B + 0x8000));
  PL (" d2f0 id=0x%08x", MMR (CFG_B + 0x10000));
  PL (" d31f7 id=0x%08x\n", MMR (CFG_B + 0xFF000));

  // PARF BDF -> SID translation as msm_pcie_config_sid does it (Android boot trace 1.5886 s): the ITS DeviceID of the EP (RID 0x100) is 0x1401 (DT msi-map)
  MMW (PARF_B + 0x2C00, 0);
  MMW (PARF_B + 0x2000, 0);
  MMW (PARF_B + 0x2054, 0x01000100);

  // 2026-10-21 memory path: RP memory window + outbound MEM iATU region, size and assign the EP BARs, read the first words of BAR0
  if (mPcKeep) {
    MMW (DBI_B + 0x20, 0x61F06020);                                 // RP memory window 0x60200000-0x61FFFFFF (the host bridge _CRS window)
    MMW (DBI_B + 0x24, 0x0000FFF0);                                 // prefetch window disabled (base > limit)
  } else {
    MMW (DBI_B + 0x20, 0x60306020);                                 // Android: memory window 0x60200000-0x603FFFFF
    MMW (DBI_B + 0x24, 0x60516041);                                 // Android: prefetch window 0x60400000-0x605FFFFF
  }                                   // RP memory base 0x60300000 / limit 0x63FFFFFF
  MMW (ATU_B + 0x400 + 0x00, 0);                                    // region 2: MEM
  MMW (ATU_B + 0x400 + 0x08, 0x60300000);
  MMW (ATU_B + 0x400 + 0x0C, 0);
  MMW (ATU_B + 0x400 + 0x10, 0x63FFFFFF);
  MMW (ATU_B + 0x400 + 0x14, 0x60300000);
  MMW (ATU_B + 0x400 + 0x18, 0);
  MMW (ATU_B + 0x400 + 0x04, 0x00000000);                           // Android has no outbound MEM region: leave it disabled
  if (!mPcKeep) {
    UINT32  Sz0, Sz2, K;

    MMW (CFG_B + 0x10, 0xFFFFFFFF);
    MMW (CFG_B + 0x14, 0xFFFFFFFF);
    Sz0 = MMR (CFG_B + 0x10);
    PL ("EP BAR0 sizing: lo=0x%08x hi=0x%08x\n", Sz0, MMR (CFG_B + 0x14));
    MMW (CFG_B + 0x18, 0xFFFFFFFF);
    Sz2 = MMR (CFG_B + 0x18);
    PL ("EP BAR2 sizing: 0x%08x\n", Sz2);
    MMW (CFG_B + 0x18, 0);
    MMW (CFG_B + 0x10, 0x60200000);
    MMW (CFG_B + 0x14, 0);
    MMW (CFG_B + 0x04, MMR (CFG_B + 0x04) | 6);
    PL ("EP cmd/sts=0x%08x bar0=0x%08x\n", MMR (CFG_B + 0x04), MMR (CFG_B + 0x10));
    for (K = 0; K < 8; K++) {
      PL ("BAR0+%02x = 0x%08x\n", K * 4, MMR (0x60200000ULL + K * 4));
    }
  }
  V = MMR (DBI_B + 0x72C);
  if (mPcKeep && (V & 0x10) && !(V & (1U << 29))) {
    PL ("KEEP: link is up (dbg1=0x%08x), leaving the rails, WLAN_EN and the link as they are for Windows\n", V);
    // 2026-10-23: Windows' pci.sys refuses a PCIe Endpoint on the root bus ("Invalid express topology", START_DEVICE fails with 0xC0000366): the EP must sit below a Root Port.
    // ECAM bus 0 (0x60000000) is the root port's own config space (DBI) and devices 1..31 answer FFFFFFFF (measured), so the MCFG covers buses 0-1 and Windows sees RP + EP.
    // The DBI class code resets to 0xFF0000 (unassigned): write the PCI-to-PCI bridge class 0x060400 the way Linux's dw_pcie_setup_rc does.
    MMW (DBI_B + 0x8BC, MMR (DBI_B + 0x8BC) | 1);                   // DBI_RO_WR_EN
    MMW (DBI_B + 0x08, (MMR (DBI_B + 0x08) & 0xFF) | 0x06040000U);
    // hide the root port's MSI capability from the capability list (PM cap at 0x40 -> next = 0x70, the PCIe cap): with it Windows asks the ITS for 32 vectors for the root port at boot, and the
    // first MAPD (Size 9, more than the ITS supports) stalls the ITS before the user-mode fixer (itsfix) is running; the root port raises no interrupts of its own
    MMW (DBI_B + 0x40, (MMR (DBI_B + 0x40) & 0xFFFF00FFU) | 0x00007000U);
    // 2026-10-29: Interrupt Pin (config 0x3D) = 1 (INTA) from the start: pci.sys then starts the root port's bus FDO at boot with the INTx resource of the DSDT's _PRT (GSI 181) instead of failing
    // (0xC0000034, FAILED_START) and being rescued later by rpfix.ps1 - and Windows never maps the root port's MSI in the ITS (DeviceID 0x1301 is no physical device of the VM: its MAPD V=0 is ERROR_UNIMPLEMENTED in Gunyah and freezes the hypervisor)
    MMW (DBI_B + 0x3C, (MMR (DBI_B + 0x3C) & 0xFFFF00FFU) | 0x00000100U);
    MMW (DBI_B + 0x8BC, MMR (DBI_B + 0x8BC) & ~1U);
    // Windows (pci.sys) takes the root port's memory window as a FIXED boot-config requirement (0x60200000-0x61FFFFFF = the whole PCI0 window) and then has no room for the root port's own BAR0
    // (CM_PROB_NORMAL_CONFLICT 0xC0000018): leave the window disabled (base > limit) so that Windows sizes and assigns the bridge windows itself
    MMW (DBI_B + 0x20, 0x0000FFF0);
    MMW (DBI_B + 0x24, 0x0000FFF0);
    // 2026-10-23: the endpoint's DMA and its MSI doorbell write (GITS_TRANSLATER 0x17150040) come from SMMU stream 0x1401 (PARF BDF->SID, DT iommu-map 0x100 -> 0x1401); UEFI leaves unmatched streams
    // faulting (sCR0.USFCFG), which would be an unhandled global fault the first time the chip raises an MSI -> give the stream an identity stage-1 context (same helper as the touch controller's stream 0xA3)
    SmmuForgetSid (0x1401);
    if (SmmuBypassSid (0x1401)) {   // SmmuIdentityWide (AArch64 format, 39 bit) took a translation fault at 0xFD914000 (CB70 FSR 0x402) - back to the AArch32 format that works for stream 0xA3
      PL ("SMMU: stream 0x1401 (WCN7850) identity mapped (0-4 GB)\n");
    } else {
      PL ("SMMU: could not map stream 0x1401\n");
    }
    PL ("root port: id=0x%08x class/rev=0x%08x hdr=0x%08x buses=0x%08x bar0=0x%08x\n", MMR (DBI_B), MMR (DBI_B + 8), MMR (DBI_B + 0xC), MMR (DBI_B + 0x18), MMR (DBI_B + 0x10));
  } else {
    if (mBhiMode) {
      // NOBOOT + \BHITEST.TXT (2026-10-30): link is up, EP BAR0 = 0x60200000, memory + bus master on.  Let the chip raise a real MSI (BHI download) and see whether the ITS turns it into an LPI.  Result in \ITSRES.TXT.
      PL ("BHITEST: running ItsTest with the BHI download as the MSI source\n");
      ItsTest ();
    }
    // undo every RPMh vote this probe made (they survive a warm reboot in AOP and broke Mu's USB init on the next boot)
    STATIC CONST CHAR8  *Names[] = { "smpc6", "smpc1", "ldok6", "ldob15", "ldoc3", "smpi4", "smpc3", "smpc2", "ldoi1", "ldoi3", "ldoe3" };
    UINT32              K, A;

    MMW (TLMM_B + 0x1000ULL * 16 + 4, 0);                           // WLAN_EN low
    MMW (TLMM_B + 0x1000ULL * 17 + 4, 0);
    if (!PC_SKIP_RAILS) {
    A = CmdDbAddr ("clka1");
    if (A != 0) {
      RpmhWrite (A, 0);
    }
    for (K = 0; K < sizeof (Names) / sizeof (Names[0]); K++) {
      A = CmdDbAddr (Names[K]);
      if (A != 0) {
        RpmhWrite (A + 0x4, 0);                                       // VRM enable = 0
      }
    }
    }
    PL ("rails/clka1 released, WLAN_EN low\n");
  }
  PL ("=== M2 end\n");
}


// DWC3 (usb_1 @0xA600000) + Qualcomm glue (QSCRATCH = base + 0xF8800): read-only look at the state ABL leaves, to see whether the
// B-session / VBUS-valid overrides (HS_PHY_CTRL bit20 UTMI_OTG_VBUS_VALID, bit28 SW_SESSVLD_SEL; SS_PHY_CTRL bit24 LANE0_PWR_PRESENT) are set.
STATIC VOID
UsbGlueProbe (VOID)
{
  CONST UINT64  U = 0x0A600000ULL;
  CONST UINT64  Q = U + 0xF8800ULL;
  UINT32        I;

  PL ("=== USB glue probe\n");
  PcEnsureMmio (GCC_B, 0x80000, "GCC");
  PL ("usb gdscr(+0x39004)=0x%08x (bit31 = power on)\n", MMR (GCC_B + 0x39004));
  if ((MMR (GCC_B + 0x39004) & 0x80000000U) == 0) {
    PL ("usb GDSC is off - not touching the controller\n");
    return;
  }
  {
    // PM8550B (sid 7) eUSB2 repeater @0xFD00 (EE0-owned): dump the whole peripheral
    UINT32  K, J;
    UINT8   B[8];

    for (K = 0; K < 0x100; K += 8) {
      if (SpmiReadBytes (7, 0xFD00 + K, 8, B)) {
        PL ("repeater +0x%02x: %02x %02x %02x %02x %02x %02x %02x %02x\n", K, B[0], B[1], B[2], B[3], B[4], B[5], B[6], B[7]);
      } else {
        PL ("repeater +0x%02x: read failed\n", K);
      }
    }
    (VOID)J;
  }
  PcEnsureMmio (U, 0xFC100, "DWC3");
  PL ("dwc3 GSNPSID=0x%08x GCTL=0x%08x GUSB2PHYCFG=0x%08x GUSB3PIPECTL=0x%08x\n", MMR (U + 0xC120), MMR (U + 0xC110), MMR (U + 0xC200), MMR (U + 0xC2C0));
  PL ("dwc3 DCFG=0x%08x DCTL=0x%08x DEVTEN=0x%08x DSTS=0x%08x GDBGLTSSM=0x%08x\n", MMR (U + 0xC700), MMR (U + 0xC704), MMR (U + 0xC708), MMR (U + 0xC70C), MMR (U + 0xC164));
  for (I = 0; I < 0x80; I += 0x10) {
    PL ("qscratch +0x%02x: %08x %08x %08x %08x\n", I, MMR (Q + I), MMR (Q + I + 4), MMR (Q + I + 8), MMR (Q + I + 12));
  }
  PL ("qscratch HS_PHY_CTRL(0x10)=0x%08x vbus_valid=%u sessvld_sel=%u | SS_PHY_CTRL(0x30)=0x%08x lane0_pwr=%u | GENERAL_CFG(0x08)=0x%08x\n",
      MMR (Q + 0x10), (MMR (Q + 0x10) >> 20) & 1, (MMR (Q + 0x10) >> 28) & 1, MMR (Q + 0x30), (MMR (Q + 0x30) >> 24) & 1, MMR (Q + 0x08));
}


// USBFN.TXT on the logdump: set the Qualcomm dwc3 glue overrides that dwc3-msm sets in device mode (nobody does it under Windows):
// HS_PHY_CTRL(0x10) bit20 UTMI_OTG_VBUS_VALID + bit28 SW_SESSVLD_SEL, SS_PHY_CTRL(0x30) bit24 LANE0_PWR_PRESENT.
STATIC VOID
UsbVbusOverride (VOID)
{
  CONST UINT64  U = 0x0A600000ULL;
  CONST UINT64  Q = U + 0xF8800ULL;

  PcEnsureMmio (GCC_B, 0x80000, "GCC");
  if ((MMR (GCC_B + 0x39004) & 0x80000000U) == 0) {
    PL ("usb override: GDSC off, skipped\n");
    return;
  }
  PcEnsureMmio (U, 0xFC100, "DWC3");
  PL ("usb override: HS_PHY_CTRL 0x%08x SS_PHY_CTRL 0x%08x before\n", MMR (Q + 0x10), MMR (Q + 0x30));
  MMW (Q + 0x10, MMR (Q + 0x10) | (1U << 20) | (1U << 28));
  MMW (Q + 0x30, MMR (Q + 0x30) | (1U << 24));
  PL ("usb override: HS_PHY_CTRL 0x%08x SS_PHY_CTRL 0x%08x after\n", MMR (Q + 0x10), MMR (Q + 0x30));
  // what dwc3_otg_start_peripheral / msm_eusb2_phy_notify_connect did on Android (ftrace rwmmio, winboot/usbtr)
  MMW (Q + 0x08, MMR (Q + 0x08) | 0x2);                                // GENERAL_CFG 0x4 -> 0x6
  {
    CONST UINT64  P = 0x088E3000ULL;                                     // usb_1_hsphy (snps eUSB2)
    // msm_eusb2_phy_init tune table as traced on Android (2026-10-17): Mu leaves 0x50/0x64 at host values (0 / 0x17171717)
    STATIC CONST UINT32  Init[][2] = { { 0x94, 0x2 }, { 0x50, 0x2 }, { 0x54, 0x09090909 }, { 0x130, 0x4 }, { 0x98, 0x0 }, { 0xB8, 0x1 }, { 0x54, 0x09090949 }, { 0x5C, 0xC8C8C8C8 }, { 0x60, 0x0 }, { 0x60, 0x0 }, { 0x58, 0x02020202 },
                                       { 0x68, 0x21212121 }, { 0x68, 0x21212121 }, { 0x6C, 0x50505050 }, { 0x70, 0x0 }, { 0x6C, 0x50505050 }, { 0x64, 0x07070717 }, { 0x7C, 0xC8C8C8C8 }, { 0x7C, 0xC8C8C8C8 }, { 0x7C, 0xC8C8C8C8 },
                                       { 0x78, 0x18181818 }, { 0x78, 0x18181818 }, { 0x64, 0x1717171F }, { 0x3C, 0x01010101 }, { 0x54, 0x4949494B }, { 0x54, 0x4B4B4B4B }, { 0x50, 0x02020200 }, { 0x64, 0x1F1F1F17 } };
    STATIC CONST UINT32  Seq[][2] = { { 0x130, 0x04040400 }, { 0x138, 0x5 }, { 0x13C, 0xC0 }, { 0x130, 0x3 }, { 0x130, 0x03030300 }, { 0x13C, 0xC0C0C000 }, { 0x130, 0x3 }, { 0x130, 0x03030300 } };
    UINT32  K;

    PcEnsureMmio (P, 0x1000, "EUSB2PHY");
    PL ("eusb2 phy before: 0x50=0x%08x 0x54=0x%08x 0x64=0x%08x 0x130=0x%08x 0x138=0x%08x 0x13c=0x%08x\n", MMR (P + 0x50), MMR (P + 0x54), MMR (P + 0x64), MMR (P + 0x130), MMR (P + 0x138), MMR (P + 0x13C));
    for (K = 0; K < sizeof (Init) / sizeof (Init[0]); K++) {
      MMW (P + Init[K][0], Init[K][1]);
    }
    PL ("eusb2 phy after init: 0x50=0x%08x 0x54=0x%08x 0x64=0x%08x\n", MMR (P + 0x50), MMR (P + 0x54), MMR (P + 0x64));
    for (K = 0; K < sizeof (Seq) / sizeof (Seq[0]); K++) {
      MMW (P + Seq[K][0], Seq[K][1]);
    }
    PL ("eusb2 phy after:  0x130=0x%08x 0x138=0x%08x 0x13c=0x%08x GENERAL_CFG=0x%08x\n", MMR (P + 0x130), MMR (P + 0x138), MMR (P + 0x13C), MMR (Q + 0x08));
  }
}


// NOBOOT + USBFN.TXT: put the dwc3 core into device mode (GCTL.PRTCAPDIR=2), HS only, set DCTL.RunStop for ~25 s and log DSTS.
// If the PC then shows an unknown USB device, the HS data path (PHY / eUSB2 repeater / D+ pull-up) works and the problem is in Windows' device stack.
STATIC VOID
UsbRunTest (VOID)
{
  CONST UINT64  U = 0x0A600000ULL;
  UINT32        I, V;

  if ((MMR (GCC_B + 0x39004) & 0x80000000U) == 0) {
    return;
  }
  PL ("usb runtest: GCTL=0x%08x DCFG=0x%08x DCTL=0x%08x\n", MMR (U + 0xC110), MMR (U + 0xC700), MMR (U + 0xC704));
  MMW (U + 0xC110, (MMR (U + 0xC110) & ~(3U << 12)) | (2U << 12));       // PRTCAPDIR = device
  MMW (U + 0xC704, 0x40000000U);                                          // DCTL.CSFTRST
  for (I = 0; I < 1000; I++) {
    if ((MMR (U + 0xC704) & 0x40000000U) == 0) {
      break;
    }
    gBS->Stall (100);
  }
  PL ("usb runtest: after soft reset DCTL=0x%08x (%u x100us)\n", MMR (U + 0xC704), I);
  MMW (U + 0xC700, (MMR (U + 0xC700) & ~7U) | 0U);                        // DCFG.DEVSPD = HS (no SuperSpeed attempt)
  MMW (U + 0xC704, 0x80000000U);                                          // DCTL.RunStop
  for (I = 0; I < 25; I++) {
    gBS->Stall (1000000);
    V = MMR (U + 0xC70C);
    PL ("usb runtest t=%u s: DCTL=0x%08x DSTS=0x%08x (connectspd=%u linkstate=%u) GDBGLTSSM=0x%08x\n", I + 1, MMR (U + 0xC704), V, V & 7, (V >> 18) & 0xF, MMR (U + 0xC164));
  }
  MMW (U + 0xC704, 0U);                                                   // stop again
  PL ("usb runtest done, DCTL=0x%08x\n", MMR (U + 0xC704));
}


// USBDEV.TXT + NOBOOT: start Qualcomm's own USB device stack (UsbDeviceDxe, EFI_USB_DEVICE_PROTOCOL, linked into the experimental Mu-usbdev image) towards the PC,
// serve enumeration for ~30 s and dump the PHY / glue / DWC3 state while the PC has the device = the GOLDEN register state for Windows' device mode.
typedef struct _MC_USB_DEVICE_PROTOCOL MC_USB_DEVICE_PROTOCOL;
typedef EFI_STATUS (*MC_USB_START) (VOID *Dev, VOID **Descs, VOID *Qual, VOID *Bos, UINT8 StrCount, VOID **Strs);
typedef EFI_STATUS (EFIAPI *MC_USB_HANDLE_EVENT) (UINT32 *Event, UINTN *Size, VOID *Data);
typedef EFI_STATUS (*MC_USB_STOP) (VOID);
struct _MC_USB_DEVICE_PROTOCOL {
  UINTN                Revision;
  MC_USB_START         Start;
  VOID                 *Send;
  MC_USB_HANDLE_EVENT  HandleEvent;
  VOID                 *AllocateTransferBuffer;
  VOID                 *FreeTransferBuffer;
  MC_USB_STOP          Stop;
  VOID                 *AbortXfer;
  VOID                 *SetEndpointStallState;
  VOID                 *StartEx;
};

STATIC VOID
UsbGoldenDump (CONST CHAR8 *Tag)
{
  CONST UINT64  U = 0x0A600000ULL;
  CONST UINT64  Q = U + 0xF8800ULL;
  CONST UINT64  H = 0x088E3000ULL;
  CONST UINT64  S = 0x088E8000ULL;
  UINT32        I, W;

  PL ("GOLDEN[%a] gdscr=0x%08x dwc3: GCTL=%08x GUCTL=%08x GUCTL1=%08x GUSB2PHYCFG=%08x GUSB3PIPECTL=%08x GFLADJ=%08x DCFG=%08x DCTL=%08x DEVTEN=%08x DSTS=%08x LTSSM=%08x\n",
      Tag, MMR (GCC_B + 0x39004), MMR (U + 0xC110), MMR (U + 0xC12C), MMR (U + 0xC11C), MMR (U + 0xC200), MMR (U + 0xC2C0), MMR (U + 0xC630), MMR (U + 0xC700), MMR (U + 0xC704), MMR (U + 0xC708), MMR (U + 0xC70C), MMR (U + 0xC164));
  for (I = 0; I < 0x100; I += 0x10) {
    PL ("GOLDEN[%a] qscratch +0x%03x: %08x %08x %08x %08x\n", Tag, I, MMR (Q + I), MMR (Q + I + 4), MMR (Q + I + 8), MMR (Q + I + 12));
  }
  for (I = 0; I < 0x160; I += 0x10) {
    PL ("GOLDEN[%a] eusb2phy +0x%03x: %08x %08x %08x %08x\n", Tag, I, MMR (H + I), MMR (H + I + 4), MMR (H + I + 8), MMR (H + I + 12));
  }
  PL ("GOLDEN[%a] eud_detect=%08x eud_enable=%08x gcc usb area:\n", Tag, MMR (0xC278000ULL), MMR (0x88E2000ULL));
  for (I = 0; I < 0x100; I += 0x10) {
    PL ("GOLDEN[%a] gcc+0x%05x: %08x %08x %08x %08x\n", Tag, 0x39000 + I, MMR (GCC_B + 0x39000 + I), MMR (GCC_B + 0x39000 + I + 4), MMR (GCC_B + 0x39000 + I + 8), MMR (GCC_B + 0x39000 + I + 12));
  }
  PcEnsureMmio (S, 0x3000, "QMP");
  for (I = 0; I < 0x3000; I += 0x10) {
    W = MMR (S + I) | MMR (S + I + 4) | MMR (S + I + 8) | MMR (S + I + 12);
    if (W != 0) {
      PL ("GOLDEN[%a] qmp +0x%04x: %08x %08x %08x %08x\n", Tag, I, MMR (S + I), MMR (S + I + 4), MMR (S + I + 8), MMR (S + I + 12));
    }
  }
}

STATIC VOID
UsbDevProbe (VOID)
{
  STATIC EFI_GUID  Guid = { 0xD9D9CE48, 0x44B8, 0x4F49, { 0x8E, 0x3E, 0x2A, 0x3B, 0x92, 0x7D, 0xC6, 0xC1 } };
  MC_USB_DEVICE_PROTOCOL  *P = NULL;
  EFI_STATUS              St;
  UINT32                  Ev, T;
  UINTN                   Sz;
  UINT8                   Data[256];
  STATIC UINT8  Dev[18] = { 18, 1, 0x00, 0x02, 0xFF, 0, 0, 64, 0x09, 0x12, 0x02, 0x00, 0x00, 0x01, 1, 2, 3, 1 };
  STATIC UINT8  Cfg[32] = { 9, 2, 32, 0, 1, 1, 0, 0xC0, 250,
                            9, 4, 0, 0, 2, 0xFF, 0, 0, 0,
                            7, 5, 0x81, 2, 0x00, 0x02, 0,
                            7, 5, 0x01, 2, 0x00, 0x02, 0 };
  STATIC UINT8  Qual[10] = { 10, 6, 0x00, 0x02, 0xFF, 0, 0, 64, 1, 0 };
  STATIC UINT16 S0[2] = { 0x0304, 0x0409 };
  STATIC UINT16 S1[4] = { 0x0308, 'r', 'm', '9' };
  STATIC UINT16 S2[6] = { 0x030C, 'M', 'u', 'C', 'h', 'a' };
  STATIC UINT16 S3[3] = { 0x0306, '0', '1' };
  VOID    *Descs[1] = { Cfg };
  VOID    *Strs[4] = { S0, S1, S2, S3 };

  PL ("=== USB device probe (Qualcomm UsbDeviceDxe)\n");
  PcEnsureMmio (GCC_B, 0x80000, "GCC");
  PcEnsureMmio (0x0A600000ULL, 0xFC100, "DWC3");
  PcEnsureMmio (0x088E3000ULL, 0x1000, "EUSB2PHY");
  UsbGoldenDump ("before");
  St = gBS->LocateProtocol (&Guid, NULL, (VOID **)&P);
  PL ("LocateProtocol(UsbDevice) -> %r P=%p\n", St, P);
  if (EFI_ERROR (St) || P == NULL) {
    return;
  }
  PL ("protocol revision 0x%lx Start=%p HandleEvent=%p\n", (UINT64)P->Revision, P->Start, P->HandleEvent);
  St = P->Start (Dev, Descs, Qual, NULL, 4, Strs);
  PL ("Start -> %r\n", St);
  if (EFI_ERROR (St)) {
    return;
  }
  for (T = 0; T < 40000; T++) {
    Sz = sizeof (Data);
    Ev = 0;
    St = P->HandleEvent (&Ev, &Sz, Data);
    if (!EFI_ERROR (St) && Ev != 0) {
      PL ("event %u size %lu data0=%08x t=%u ms\n", Ev, (UINT64)Sz, *(UINT32 *)Data, T);
    }
    if (T == 2000 || T == 10000 || T == 20000) {
      PL ("t=%u ms dsts=%08x dctl=%08x\n", T, MMR (0x0A60C70CULL), MMR (0x0A60C704ULL));
    }
    if (T == 12000) {
      UsbGoldenDump ("connected");
    }
    gBS->Stall (1000);
  }
  UsbGoldenDump ("end");
  St = P->Stop ();
  PL ("Stop -> %r\n", St);
}

// what PIL's partition lookup sees: protocol FE2555BE-D716-4686-B9D0-79DB5921B70D (a GPT-entry-like struct, name at +0x38) on BlockIo handles
STATIC VOID
PartProbe (VOID)
{
  STATIC EFI_GUID  FeGuid = { 0xFE2555BE, 0xD716, 0x4686, { 0xB9, 0xD0, 0x79, 0xDB, 0x59, 0x21, 0xB7, 0x0D } };
  EFI_HANDLE  *H = NULL;
  UINTN       N = 0, I, J, K, Fe = 0, Sfs = 0, Shown = 0;
  EFI_GUID    **Pr;
  UINTN       PrN;

  if (EFI_ERROR (gBS->LocateHandleBuffer (ByProtocol, &gEfiBlockIoProtocolGuid, NULL, &N, &H))) {
    return;
  }
  for (I = 0; I < N; I++) {
    BOOLEAN  HasFe = FALSE, HasSfs = FALSE;
    if (!EFI_ERROR (gBS->ProtocolsPerHandle (H[I], &Pr, &PrN))) {
      for (J = 0; J < PrN; J++) {
        if (CompareGuid (Pr[J], &FeGuid)) {
          HasFe = TRUE;
        }
        if (CompareGuid (Pr[J], &gEfiSimpleFileSystemProtocolGuid)) {
          HasSfs = TRUE;
        }
      }
      if (HasFe && Shown < 6) {
        VOID  *Ent = NULL;
        CHAR16  Name[24];
        if (!EFI_ERROR (gBS->HandleProtocol (H[I], &FeGuid, &Ent)) && Ent != NULL) {
          CONST UINT16  *Nm = (CONST UINT16 *)((UINTN)Ent + 0x38);
          for (K = 0; K < 23 && Nm[K] != 0; K++) {
            Name[K] = Nm[K];
          }
          Name[K] = 0;
          PL ("PART fe handle %p ent=%p name=%s sfs=%d\n", H[I], Ent, Name, HasSfs);
        }
        Shown++;
      }
      if (HasFe) {
        Fe++;
      }
      if (HasSfs) {
        Sfs++;
      }
      FreePool (Pr);
    }
  }
  PL ("PART blockio handles=%lu with FE2555BE=%lu with SFS=%lu\n", (UINT64)N, (UINT64)Fe, (UINT64)Sfs);
  FreePool (H);
}

STATIC EFI_HANDLE  mRmH[8];
STATIC VOID        *mRmIf[8];
STATIC UINTN       mRmCount;

// Mu's PartitionDxe does not install Qualcomm's per-partition GPT-entry protocol FE2555BE-D716-4686-B9D0-79DB5921B70D that PIL's partition lookup needs
// (interface = EFI_PARTITION_ENTRY, name at +0x38).  Install it on modem_b only (sde partition 37, start LBA 355418, type basic-data): PIL requires exactly one match of the type GUID.
STATIC VOID
PartFixModem (VOID)
{
  STATIC EFI_GUID  FeGuid = { 0xFE2555BE, 0xD716, 0x4686, { 0xB9, 0xD0, 0x79, 0xDB, 0x59, 0x21, 0xB7, 0x0D } };
  STATIC EFI_GUID  BasicData = { 0xEBD0A0A2, 0xB9E5, 0x4433, { 0x87, 0xC0, 0x68, 0xB6, 0xB7, 0x26, 0x99, 0xC7 } };
  EFI_HANDLE  *H = NULL;
  UINTN       N = 0, I;

  if (EFI_ERROR (gBS->LocateHandleBuffer (ByProtocol, &gEfiBlockIoProtocolGuid, NULL, &N, &H))) {
    return;
  }
  for (I = 0; I < N; I++) {
    EFI_DEVICE_PATH_PROTOCOL  *Dp = NULL, *Node;

    if (EFI_ERROR (gBS->HandleProtocol (H[I], &gEfiDevicePathProtocolGuid, (VOID **)&Dp)) || Dp == NULL) {
      continue;
    }
    for (Node = Dp; !IsDevicePathEnd (Node); Node = NextDevicePathNode (Node)) {
      if (DevicePathType (Node) == MEDIA_DEVICE_PATH && DevicePathSubType (Node) == MEDIA_HARDDRIVE_DP) {
        HARDDRIVE_DEVICE_PATH  *Hd = (HARDDRIVE_DEVICE_PATH *)Node;
        if (Hd->PartitionNumber == 37 && Hd->PartitionStart == 355418ULL && Hd->SignatureType == 2) {
          UINT8  *E = AllocateZeroPool (128);
          UINTN  K;
          EFI_STATUS  St;
          STATIC CONST CHAR16  Nm[] = L"modem_b";

          CopyMem (E + 0, &BasicData, 16);
          CopyMem (E + 16, Hd->Signature, 16);
          *(UINT64 *)(E + 32) = Hd->PartitionStart;
          *(UINT64 *)(E + 40) = Hd->PartitionStart + Hd->PartitionSize - 1;
          for (K = 0; K < 8; K++) {
            *(UINT16 *)(E + 56 + 2 * K) = Nm[K];
          }
          St = gBS->InstallProtocolInterface (&H[I], &FeGuid, EFI_NATIVE_INTERFACE, E);
          PL ("PART modem_b handle %p: installed FE2555BE entry -> %r\n", H[I], St);
        }
      }
    }
  }
  // PIL wants exactly ONE handle carrying a protocol whose GUID is the partition type GUID (basic data): Mu's PartitionDxe puts it on every basic-data partition (modem_b and the NTFS windows one) -> drop it from the others
  {
    UINTN  Removed = 0, Kept = 0;
    for (I = 0; I < N; I++) {
      VOID  *If = NULL;
      if (!EFI_ERROR (gBS->HandleProtocol (H[I], &BasicData, &If))) {
        BOOLEAN  IsModem = FALSE;
        VOID     *Fe = NULL;
        if (!EFI_ERROR (gBS->HandleProtocol (H[I], &FeGuid, &Fe)) && Fe != NULL) {
          IsModem = TRUE;
        }
        if (IsModem) {
          Kept++;
        } else if (!EFI_ERROR (gBS->UninstallProtocolInterface (H[I], &BasicData, If))) {
          if (mRmCount < 8) {
            mRmH[mRmCount] = H[I];
            mRmIf[mRmCount] = If;
            mRmCount++;
          }
          Removed++;
        }
      }
    }
    PL ("PART basic-data protocol: kept=%lu removed from others=%lu\n", (UINT64)Kept, (UINT64)Removed);
  }
  FreePool (H);
}

STATIC VOID
PartRestore (VOID)
{
  STATIC EFI_GUID  BasicData = { 0xEBD0A0A2, 0xB9E5, 0x4433, { 0x87, 0xC0, 0x68, 0xB6, 0xB7, 0x26, 0x99, 0xC7 } };
  UINTN  I;

  for (I = 0; I < mRmCount; I++) {
    gBS->InstallProtocolInterface (&mRmH[I], &BasicData, EFI_NATIVE_INTERFACE, mRmIf[I]);
  }
  mRmCount = 0;
}

// After the ADSP is up: PmicGlinkDxe protocol 7429EB07-F2E3-4A6B-AA96-C909CD956EF7 (only QcomChargerDxe uses it): [0]=revision, then plain functions without This.
// ChargerLibTarget_LinkChargerFW: fn7 = Connect(), fn9 = Connect (ChargerPD logging), fn8 = GetStatus(UINT8 *Connected), polled once a second for 20 s.
STATIC VOID
PmicGlinkLink (VOID)
{
  STATIC EFI_GUID  Guid = { 0x7429EB07, 0xF2E3, 0x4A6B, { 0xAA, 0x96, 0xC9, 0x09, 0xCD, 0x95, 0x6E, 0xF7 } };
  typedef UINTN (EFIAPI *F0) (VOID);
  typedef UINTN (EFIAPI *F1) (UINT8 *);
  UINT64      *P = NULL;
  EFI_STATUS  St;
  UINTN       R;
  UINT8       Up = 0;
  UINT32      I;

  St = gBS->LocateProtocol (&Guid, NULL, (VOID **)&P);
  PL ("LocateProtocol(PmicGlink) -> %r P=%p revision 0x%lx\n", St, P, P ? P[0] : 0);
  if (EFI_ERROR (St) || P == NULL) {
    return;
  }
  R = ((F0)P[8]) ();
  PL ("PmicGlink Connect -> 0x%lx\n", (UINT64)R);
  R = ((F0)P[10]) ();
  PL ("PmicGlink Connect(logs) -> 0x%lx\n", (UINT64)R);
  for (I = 0; I < 20; I++) {
    gBS->Stall (1000000);
    Up = 0xEE;
    R = ((F1)P[9]) (&Up);
    PL ("PmicGlink GetStatus t=%u -> 0x%lx connected=%u\n", I, (UINT64)R, Up);
    if (R == 0 && Up == 1) {
      break;
    }
  }
  {
    typedef UINTN (EFIAPI *F2) (UINT32, VOID *);
    UINT8  Out[64];
    UINTN  K;

    for (K = 0; K < 2; K++) {
      F2  Fn = (F2)P[K == 0 ? 13 : 20];
      SetMem (Out, sizeof (Out), 0xEE);
      R = Fn (0x10, Out);
      PL ("PmicGlink battmgr-test fn%u(0x10) -> 0x%lx out: %08x %08x %08x %08x\n", K == 0 ? 12 : 19, (UINT64)R, ((UINT32 *)Out)[0], ((UINT32 *)Out)[1], ((UINT32 *)Out)[2], ((UINT32 *)Out)[3]);
    }
  }
}

// UCSI over pmic_glink through PmicGlinkDxe's own TX path: PmicGlinkDxe only sends battmgr messages itself (owner 0x800A/0x800D) but its RX handler already files owner 0x800B (USBC)
// replies into globals: UCSI buffer (48 bytes) at image+0xA258, notification at +0xA288, write ack flags at +0xA2A8/+0xA2A9.  The generic send+poll routine is image+0x42A0(unused, msg, size).
typedef UINTN (EFIAPI *MC_PG_SEND) (UINT32 Unused, VOID *Msg, UINTN Size);

STATIC VOID IpccIsrReport (CONST CHAR8 *Tag);
STATIC VOID IpccDxeDump (VOID);
STATIC VOID IpccCfgScan (VOID);
STATIC VOID SmemDump (CONST CHAR8 *Tag);
STATIC VOID GlinkFifoDump (CONST CHAR8 *Tag);
STATIC VOID Smp2pDump (CONST CHAR8 *Tag);
STATIC VOID Smp2pPublish (VOID);
STATIC VOID RtrOpen (UINT64 Base, CONST CHAR8 *NameIn);
STATIC UINT8 *SmemItem (UINT16 Host1, UINT16 Item, UINT32 *OutSize);
STATIC EFI_EVENT mIpccTimer;
STATIC UINT64   mRtrHandle;
STATIC BOOLEAN  mRxSnapOn;
STATIC UINT32   *mRxDesc;
STATIC UINT8    *mRxFifo;
STATIC UINT32   mRxLast, mRxLogLen;
STATIC UINT8    mRxLog[0x40000];
STATIC VOID PmicSurvey (VOID);
STATIC UINT32 mDbgOwner = 0x800F;
STATIC UINT64 mPgBase;
STATIC VOID PmicDbgCall (UINT64 Base, CONST CHAR8 *Tag, UINT32 Opcode, UINT32 A, UINT32 B, UINT32 C, UINT32 D, UINT32 RxWaitMs, UINT32 HandleOff);

// UCSI over pmic_glink through PmicGlinkDxe's own TX path (see ucsi_patch.py): UCSI buffer (48 bytes) at image+0xA258, generic send+poll routine image+0x42A0(unused, msg, size).
STATIC VOID
UcsiDump (CONST CHAR8 *Tag, CONST UINT8 *B)
{
  PL ("UCSI[%a] ver=%04x cci=%08x ctrl=%016lx in=%08x %08x %08x %08x out=%08x\n", Tag, *(CONST UINT16 *)(B + 0), *(CONST UINT32 *)(B + 4), *(CONST UINT64 *)(B + 8),
      *(CONST UINT32 *)(B + 16), *(CONST UINT32 *)(B + 20), *(CONST UINT32 *)(B + 24), *(CONST UINT32 *)(B + 28), *(CONST UINT32 *)(B + 32));
}

// ---- mini glink-native for channel 8 (PMIC_RTR_ADSP_APPS), used after GlinkDxe's poll is stopped.  FIFO layout: SMEM item 479 = AP->ADSP, 480 = ADSP->AP, item 478 = descriptor
//   (tx tail, tx head, rx tail, rx head).  Messages are 8-byte aligned: TX_DATA = 16-byte header {cmd|ch<<16, riid, size, left} + payload; RX_DONE_W_REUSE = {0xE|ch<<16, riid}.
//   The ADSP's receive intents for this channel (ids 0..5, 512 B) are tracked in mMgFree and given back by the ADSP's own RX_DONE messages.
STATIC UINT32  *mMgD;
STATIC UINT8   *mMgTx, *mMgRx;
STATIC UINT32  mMgPos, mMgFree, mMgMsgLen, mMgMsgSeq, mMgAsmLen;
STATIC UINT8   mMgMsg[1024], mMgAsm[1024];
STATIC UINT32  mMgFree9, mMgMsgLen9, mMgMsgSeq9, mMgAsmLen9;      // channel 9: ADSP intents are ids 6..11 (bit = id-6)
STATIC UINT8   mMgMsg9[9000], mMgAsm9[9000];

STATIC BOOLEAN
MgInit (VOID)
{
  UINT32  Sz;

  mMgD  = (UINT32 *)SmemItem (2, 478, &Sz);
  mMgTx = SmemItem (2, 479, &Sz);
  mMgRx = SmemItem (2, 480, &Sz);
  if (mMgD == NULL || mMgTx == NULL || mMgRx == NULL) {
    return FALSE;
  }
  mMgPos = mMgD[3];
  mMgFree = 0x3F;
  mMgMsgLen = 0;
  mMgMsgSeq = 0;
  mMgAsmLen = 0;
  mMgFree9 = 0x3F;
  mMgMsgLen9 = 0;
  mMgMsgSeq9 = 0;
  mMgAsmLen9 = 0;
  return TRUE;
}

STATIC VOID
MgTxWords (CONST UINT32 *W, UINT32 N)
{
  UINT32  Head = mMgD[1], I;

  for (I = 0; I < N; I++) {
    *(volatile UINT32 *)(mMgTx + Head) = W[I];
    Head = (Head + 4) & 0x3FFF;
  }
  MemoryFence ();
  mMgD[1] = Head;
  MemoryFence ();
  MMW (IPCC_B + 0x0C, 0x30000);   // IPCC SEND_ID: client 3 (ADSP), signal 0 (glink)
}

STATIC VOID
MgPoll (VOID)
{
  UINT32  Head = mMgD[3];
  UINT32  Avail;

  while (mMgPos != Head) {
    Avail = (Head - mMgPos) & 0x3FFF;
    if (Avail < 8) {
      break;
    }
    {
      UINT32  W0 = *(volatile UINT32 *)(mMgRx + mMgPos);
      UINT32  W1 = *(volatile UINT32 *)(mMgRx + ((mMgPos + 4) & 0x3FFF));
      UINT32  Cmd = W0 & 0xFFFF, Ch = W0 >> 16, Adv = 8;

      if (Cmd == 9 || Cmd == 12 || Cmd == 13) {         // TX_DATA(+CONT)
        UINT32  Size, Left, I;
        if (Avail < 16) {
          break;
        }
        Size = *(volatile UINT32 *)(mMgRx + ((mMgPos + 8) & 0x3FFF));
        Left = *(volatile UINT32 *)(mMgRx + ((mMgPos + 12) & 0x3FFF));
        Adv = 16 + ((Size + 7) & ~7U);
        if (Avail < Adv) {
          break;
        }
        if (Ch == 9) {
          for (I = 0; I < Size && mMgAsmLen9 < sizeof (mMgAsm9); I++) {
            mMgAsm9[mMgAsmLen9++] = mMgRx[(mMgPos + 16 + I) & 0x3FFF];
          }
          if (Left == 0) {
            UINT32  Rd9[2];
            CopyMem (mMgMsg9, mMgAsm9, mMgAsmLen9);
            mMgMsgLen9 = mMgAsmLen9;
            mMgAsmLen9 = 0;
            mMgMsgSeq9++;
            Rd9[0] = 0x0000000E | (9 << 16);
            Rd9[1] = W1;
            MgTxWords (Rd9, 2);
          }
        }
        if (Ch == 8) {
          for (I = 0; I < Size && mMgAsmLen < sizeof (mMgAsm); I++) {
            mMgAsm[mMgAsmLen++] = mMgRx[(mMgPos + 16 + I) & 0x3FFF];
          }
          if (Left == 0) {
            UINT32  Rd[2];
            CopyMem (mMgMsg, mMgAsm, mMgAsmLen);
            mMgMsgLen = mMgAsmLen;
            mMgAsmLen = 0;
            mMgMsgSeq++;
            Rd[0] = 0x0000000E | (8 << 16);   // RX_DONE_W_REUSE: hand the intent back
            Rd[1] = W1;
            MgTxWords (Rd, 2);
          }
        }
      } else if (Cmd == 5) {                             // INTENT: header + n * {size,id}
        Adv = 8 + 8 * W1;
        if (Avail < Adv) {
          break;
        }
      } else if (Cmd == 2) {                             // OPEN: header + name
        Adv = 8 + (((W1 & 0xFFFF) + 7) & ~7U);
        if (Avail < Adv) {
          break;
        }
      } else if ((Cmd == 14 || Cmd == 6) && Ch == 8 && W1 < 6) {   // ADSP released one of its intents
        mMgFree |= 1U << W1;
      } else if ((Cmd == 14 || Cmd == 6) && Ch == 9 && W1 >= 6 && W1 < 12) {
        mMgFree9 |= 1U << (W1 - 6);
      }
      mMgPos = (mMgPos + Adv) & 0x3FFF;
    }
  }
  mMgD[2] = mMgPos;   // free the ring for the ADSP
}

STATIC BOOLEAN
MgSend (CONST VOID *Msg, UINT32 Size)
{
  UINT32  Words[300], I, T, Ri = 0xFF;
  UINT32  Padded = (Size + 7) & ~7U;

  for (T = 0; T < 1000 && Ri == 0xFF; T++) {
    MgPoll ();
    for (I = 0; I < 6; I++) {
      if ((mMgFree & (1U << I)) != 0) {
        Ri = I;
        break;
      }
    }
    if (Ri == 0xFF) {
      gBS->Stall (1000);
    }
  }
  if (Ri == 0xFF || Padded > sizeof (Words) - 16) {
    return FALSE;
  }
  mMgFree &= ~(1U << Ri);
  SetMem (Words, sizeof (Words), 0);
  Words[0] = 0x00000009 | (8 << 16);
  Words[1] = Ri;
  Words[2] = Size;
  Words[3] = 0;
  CopyMem (Words + 4, Msg, Size);
  MgTxWords (Words, 4 + Padded / 4);
  return TRUE;
}

// wait for a reply with the given owner/opcode; the message ends up in mMgMsg
STATIC BOOLEAN
MgWait (UINT32 Owner, UINT32 Opcode, UINT32 TimeoutMs)
{
  UINT32  T, Seen = mMgMsgSeq;

  for (T = 0; T < TimeoutMs; T++) {
    MgPoll ();
    if (mMgMsgSeq != Seen) {
      UINT32  *W = (UINT32 *)mMgMsg;
      Seen = mMgMsgSeq;
      if (W[0] == Owner && W[2] == Opcode) {
        return TRUE;
      }
    }
    gBS->Stall (1000);
  }
  return FALSE;
}

STATIC BOOLEAN  mRtrQuiet;

STATIC BOOLEAN
MgSend9 (CONST VOID *Msg, UINT32 Size)
{
  UINT32  Words[40], I, T, Ri = 0xFF;
  UINT32  Padded = (Size + 7) & ~7U;

  for (T = 0; T < 1000 && Ri == 0xFF; T++) {
    MgPoll ();
    for (I = 0; I < 6; I++) {
      if ((mMgFree9 & (1U << I)) != 0) {
        Ri = I;
        break;
      }
    }
    if (Ri == 0xFF) {
      gBS->Stall (1000);
    }
  }
  if (Ri == 0xFF || Padded > sizeof (Words) - 16) {
    return FALSE;
  }
  mMgFree9 &= ~(1U << Ri);
  SetMem (Words, sizeof (Words), 0);
  Words[0] = 0x00000009 | (9 << 16);
  Words[1] = Ri + 6;
  Words[2] = Size;
  Words[3] = 0;
  CopyMem (Words + 4, Msg, Size);
  MgTxWords (Words, 4 + Padded / 4);
  return TRUE;
}

// ADSP charger ULog (charger-ulog-glink protocol on PMIC_LOGS): request {0x800A, 1, 0x18, 0x2000} -> 12-byte header + up to 8 KB of text.  The ring keeps the FIRST 16 KB after boot and drops later
// lines until it has been read, so drain it once early (UlogDrain) and the later reads (UlogShow) show what happened since.
STATIC UINT32
UlogFetch (VOID)
{
  UINT32  Rq[4], T, Seen = mMgMsgSeq9;

  Rq[0] = 0x800A; Rq[1] = 1; Rq[2] = 0x18; Rq[3] = 0x2000;
  if (!MgSend9 (Rq, 16)) {
    return 0;
  }
  for (T = 0; T < 1500; T++) {
    MgPoll ();
    if (mMgMsgSeq9 != Seen) {
      return mMgMsgLen9 > 12 ? mMgMsgLen9 - 12 : 0;
    }
    gBS->Stall (1000);
  }
  return 0;
}

STATIC VOID
UlogDrain (VOID)
{
  UINT32  I, N;

  for (I = 0; I < 6; I++) {
    N = UlogFetch ();
    PL ("ULOG drain %u: %u bytes\n", I, N);
    if (N == 0 || mMgMsg9[12] == 0) {
      break;
    }
  }
}

STATIC VOID
UlogShow (CONST CHAR8 *Tag)
{
  UINT32  N = UlogFetch (), I, L = 0;
  CHAR8   Line[200];

  PL ("ULOG[%a] %u bytes\n", Tag, N);
  for (I = 0; I < N; I++) {
    UINT8  C = mMgMsg9[12 + I];
    if (C == 0) {
      break;
    }
    if (C == 10 || L >= sizeof (Line) - 1) {
      Line[L] = 0;
      if (L > 0) {
        PL ("ULOG> %a\n", Line);
      }
      L = 0;
      if (C == 10) {
        continue;
      }
    }
    Line[L++] = (C >= 32 && C < 127) ? (CHAR8)C : '.';
  }
  if (L > 0) {
    Line[L] = 0;
    PL ("ULOG> %a\n", Line);
  }
}

// UCSI buffer (48 B) in the reply: ver(2) rsv(2) CCI(4) CONTROL(8) MESSAGE_IN(16) MESSAGE_OUT(16)
STATIC BOOLEAN
RtrUcsiRead (UINT8 *Buf48)
{
  UINT32  Rq[3];

  Rq[0] = 0x800B; Rq[1] = 1; Rq[2] = 0x11;
  if (!MgSend (Rq, 12) || !MgWait (0x800B, 0x11, 1000) || mMgMsgLen < 12 + 48) {
    return FALSE;
  }
  CopyMem (Buf48, mMgMsg + 12, 48);
  return TRUE;
}

STATIC VOID
RtrUcsiShow (CONST CHAR8 *Tag, CONST UINT8 *B)
{
  PL ("UCSI.RTR[%a] ver=%04x cci=%08x ctrl=%016lx in=%08x %08x %08x %08x out=%08x %08x %08x %08x\n", Tag, *(CONST UINT16 *)B, *(CONST UINT32 *)(B + 4), *(CONST UINT64 *)(B + 8),
      *(CONST UINT32 *)(B + 16), *(CONST UINT32 *)(B + 20), *(CONST UINT32 *)(B + 24), *(CONST UINT32 *)(B + 28), *(CONST UINT32 *)(B + 32), *(CONST UINT32 *)(B + 36), *(CONST UINT32 *)(B + 40), *(CONST UINT32 *)(B + 44));
}

// write CONTROL, then poll CCI until a completion bit shows, acknowledge, return the buffer after completion
STATIC UINT32
RtrUcsiCmd (CONST CHAR8 *Tag, UINT64 Control, UINT8 *Out48)
{
  UINT32  Rq[16];
  UINT8   B[48];
  UINT32  T, Cci = 0;

  ZeroMem (Rq, sizeof (Rq));
  ZeroMem (B, sizeof (B));
  Rq[0] = 0x800B; Rq[1] = 1; Rq[2] = 0x12;
  CopyMem ((UINT8 *)Rq + 12 + 8, &Control, 8);
  if (!MgSend (Rq, 64)) {
    PL ("UCSI.RTR %a: send failed\n", Tag);
    return 0xFFFFFFFF;
  }
  MgWait (0x800B, 0x12, 500);
  for (T = 0; T < 30; T++) {
    gBS->Stall (100000);
    if (!RtrUcsiRead (B)) {
      continue;
    }
    Cci = *(UINT32 *)(B + 4);
    if ((Cci & 0xC8000000U) != 0) {   // command complete / error / reset complete
      break;
    }
  }
  if (!mRtrQuiet) {
    RtrUcsiShow (Tag, B);
  }
  if (Out48 != NULL) {
    CopyMem (Out48, B, 48);
  }
  if ((Cci & 0x80000000U) != 0) {   // acknowledge command completion
    UINT32  A[16];
    UINT64  Ack = 0x04 | (1ULL << 17);
    ZeroMem (A, sizeof (A));
    A[0] = 0x800B; A[1] = 1; A[2] = 0x12;
    CopyMem ((UINT8 *)A + 12 + 8, &Ack, 8);
    MgSend (A, 64);
    MgWait (0x800B, 0x12, 300);
    gBS->Stall (200000);
    RtrUcsiRead (B);
  }
  return Cci;
}

// UCSIHOST.TXT: make the phone a USB host / VBUS source on connector 1 through the ADSP (UCSI), after the PC cable has been removed and an OTG adapter + device is plugged in.
STATIC UINT32
RtrConnStatus (UINT32 *W0, UINT32 *W1)
{
  UINT8   B[48];
  UINT32  Cci;

  mRtrQuiet = TRUE;
  Cci = RtrUcsiCmd ("st", 0x12 | (1ULL << 16), B);
  mRtrQuiet = FALSE;
  *W0 = *(UINT32 *)(B + 16);
  *W1 = *(UINT32 *)(B + 20);
  return Cci;
}

STATIC VOID
EFIAPI
WdtPetCb (IN EFI_EVENT Ev, IN VOID *Ctx)
{
  ARM_SMC_ARGS  Args = { 0 };

  Args.Arg0 = 0x86000007U;   // GH_WDT_PING
  ArmCallSmc (&Args);
}

STATIC VOID
RtrUcsiHostTest (VOID)
{
  UINT32  T, W0, W1, L0 = 0xFFFFFFFF, L1 = 0xFFFFFFFF, Cci;
  UINT8   B[48];
  BOOLEAN Gone = FALSE;
  EFI_EVENT  PetEv = NULL;

  {
    EFI_STATUS  Sw = gBS->CreateEvent (EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, WdtPetCb, NULL, &PetEv);
    if (!EFI_ERROR (Sw)) {
      gBS->SetTimer (PetEv, TimerPeriodic, 10000000);   // GH_WDT_PING every second (the hypervisor limits the timeout to ~32 s, SET_TIME with more does not stick)
    }
  }
  PL ("HOSTTEST: step 1 - waiting for the PC cable to be unplugged (up to 240 s)\n");
  for (T = 0; T < 240; T++) {
    Cci = RtrConnStatus (&W0, &W1);
    if (W0 != L0 || W1 != L1) {
      PL ("HOSTTEST: t=%u cci=%08x status=%08x %08x connected=%u powerdir=%u opmode=%u\n", T, Cci, W0, W1, (W0 >> 19) & 1, (W0 >> 20) & 1, (W0 >> 16) & 7);
      L0 = W0; L1 = W1;
    }
    if (((W0 >> 19) & 1) == 0) {
      Gone = TRUE;
      break;
    }
    gBS->Stall (1000000);
  }
  PL ("HOSTTEST: cable gone=%u -> step 2: Rp-only (source), PDR source, UOR DFP\n", Gone);
  RtrUcsiCmd ("set-ccom-rp", 0x08 | (1ULL << 16) | (1ULL << 23), B);
  RtrUcsiCmd ("set-pdr-source", 0x0B | (1ULL << 16) | (1ULL << 23), B);
  RtrUcsiCmd ("set-uor-dfp", 0x09 | (1ULL << 16) | (1ULL << 23), B);
  PL ("HOSTTEST: step 3 - waiting for a device to be attached (up to 240 s)\n");
  L0 = 0xFFFFFFFF; L1 = 0xFFFFFFFF;
  for (T = 0; T < 240; T++) {
    Cci = RtrConnStatus (&W0, &W1);
    if (W0 != L0 || W1 != L1) {
      PL ("HOSTTEST: t=%u cci=%08x status=%08x %08x connected=%u powerdir=%u opmode=%u\n", T, Cci, W0, W1, (W0 >> 19) & 1, (W0 >> 20) & 1, (W0 >> 16) & 7);
      L0 = W0; L1 = W1;
    }
    gBS->Stall (1000000);
  }
  PL ("HOSTTEST: step 4 - restore DRP\n");
  RtrUcsiCmd ("set-ccom-drp", 0x08 | (1ULL << 16) | (4ULL << 23), B);
  RtrUcsiCmd ("set-pdr-sink", 0x0B | (1ULL << 16) | (2ULL << 23), B);
  RtrUcsiCmd ("set-uor-ufp", 0x09 | (1ULL << 16) | (2ULL << 23), B);
  RtrConnStatus (&W0, &W1);
  PL ("HOSTTEST: end status=%08x %08x\n", W0, W1);
  if (PetEv != NULL) {
    gBS->SetTimer (PetEv, TimerCancel, 0);   // stop petting: the watchdog bites within ~30 s and the phone drops to the dump mode (console capture needs the PC cable again)
  }
}

// Event-driven version of the host test for the Windows path (WINDELAY.TXT): wait for the PC cable to go away, ask the ADSP for the DFP/source roles, wait for a device, then let Windows start.
STATIC VOID
RtrHostPrepare (VOID)
{
  UINT32  T, W0, W1, L0 = 0xFFFFFFFF, L1 = 0xFFFFFFFF, Cci;
  UINT8   B[48];
  BOOLEAN Gone = FALSE;

  UlogDrain ();
  PL ("HOSTPREP: waiting for the PC cable to be unplugged (up to 200 s)\n");
  for (T = 0; T < 200; T++) {
    Cci = RtrConnStatus (&W0, &W1);
    if (W0 != L0 || W1 != L1) {
      PL ("HOSTPREP: t=%u cci=%08x status=%08x %08x connected=%u powerdir=%u opmode=%u\n", T, Cci, W0, W1, (W0 >> 19) & 1, (W0 >> 20) & 1, (W0 >> 16) & 7);
      L0 = W0; L1 = W1;
    }
    if (((W0 >> 19) & 1) == 0) {
      Gone = TRUE;
      break;
    }
    gBS->Stall (1000000);
  }
  PL ("HOSTPREP: cable gone=%u -> SET_CCOM Rp / SET_PDR source / SET_UOR DFP\n", Gone);
  RtrUcsiCmd ("prep-ccom-rp", 0x08 | (1ULL << 16) | (1ULL << 23), B);
  RtrUcsiCmd ("prep-pdr-source", 0x0B | (1ULL << 16) | (1ULL << 23), B);
  RtrUcsiCmd ("prep-uor-dfp", 0x09 | (1ULL << 16) | (1ULL << 23), B);
  PL ("HOSTPREP: waiting for a device (up to 150 s)\n");
  L0 = 0xFFFFFFFF; L1 = 0xFFFFFFFF;
  for (T = 0; T < 150; T++) {
    Cci = RtrConnStatus (&W0, &W1);
    if (W0 != L0 || W1 != L1) {
      PL ("HOSTPREP: t=%u cci=%08x status=%08x %08x connected=%u powerdir=%u opmode=%u\n", T, Cci, W0, W1, (W0 >> 19) & 1, (W0 >> 20) & 1, (W0 >> 16) & 7);
      L0 = W0; L1 = W1;
    }
    if (((W0 >> 19) & 1) != 0 && ((W0 >> 20) & 1) != 0) {   // connected and we are the source
      gBS->Stall (3000000);
      PL ("HOSTPREP: device attached, reading the ADSP log\n");
      UlogShow ("after-attach-1");
      gBS->Stall (2000000);
      UlogShow ("after-attach-2");
      gBS->Stall (3000000);
      UlogShow ("after-attach-3");
      PL ("HOSTPREP: done, starting Windows\n");
      return;
    }
    gBS->Stall (1000000);
  }
  PL ("HOSTPREP: no device within the time limit, starting Windows anyway\n");
}

STATIC VOID
RtrUcsiSession (VOID)
{
  UINT8   B[48];
  UINT32  Pan[4];

  if (mIpccTimer != NULL) {
    gBS->SetTimer (mIpccTimer, TimerCancel, 0);   // from now on this code is the only glink user
  }
  gBS->Stall (200000);
  if (!MgInit ()) {
    PL ("UCSI.RTR: mini glink init failed\n");
    return;
  }
  Pan[0] = 0x800C; Pan[1] = 1; Pan[2] = 0x15; Pan[3] = 1;   // altmode PAN_EN, like the Linux driver
  MgSend (Pan, 16);
  gBS->Stall (200000);
  if (RtrUcsiRead (B)) {
    RtrUcsiShow ("read", B);
  } else {
    PL ("UCSI.RTR: first read failed\n");
    return;
  }
  RtrUcsiCmd ("ppm-reset", 0x01, B);
  RtrUcsiCmd ("notif-en", 0x05 | (0x8001ULL << 16), B);
  RtrUcsiCmd ("get-cap", 0x06, B);
  RtrUcsiCmd ("conn1-status", 0x12 | (1ULL << 16), B);
  RtrUcsiCmd ("conn2-status", 0x12 | (2ULL << 16), B);
  if (SelfFileExists (L"\\UCSIHOST.TXT")) {
    RtrUcsiHostTest ();
  }
}

// UCSIINIT.TXT (Windows path too): bring the ADSP's UCSI/PD stack to the state the Linux driver leaves it in (altmode PAN_EN, PPM reset, notifications on),
// then leave the ADSP running on its own: it switches Type-C roles and drives VBUS by itself (hostB: device attached -> Source/DFP).
// ---- battery snapshot through the ADSP's battmgr (pmic_glink owner 0x800A, qti_battery_charger protocol, captured from Android with kprobes on battery_chg_write/_callback):
//   request  {0x800A, 1, opcode, battery_id, property_id, 0}  (24 bytes)      opcode 0x30 = battery property get, 0x32 = USB property get
//   reply    {0x800A, 1, opcode, property_id, value, 0}
//   battery props: 0 status, 1 health, 2 present, 4 capacity(0.01 %), 7 voltage(uV), 9 current(raw), 0xC temp(0.01 degC), 0xF cycle count, 0x10 design capacity(uAh), 0x11 full capacity(uAh)
//   usb props: 0 online, 2 voltage(uV), 4 current limit(uA)
// The result is kept at physical 0xD7FF1000 for Windows (rm9io): u32 magic 'BATT', u32 count, then {u32 opcode<<16|prop, u32 value} pairs.
#define BATT_MAGIC_ADDR  0xD7FF1000ULL

STATIC BOOLEAN
BattProp (UINT32 Opcode, UINT32 Prop, UINT32 *Val)
{
  UINT32  Rq[6], Try;

  for (Try = 0; Try < 3; Try++) {
    Rq[0] = 0x800A; Rq[1] = 1; Rq[2] = Opcode; Rq[3] = 0; Rq[4] = Prop; Rq[5] = 0;
    if (!MgSend (Rq, 24)) {
      return FALSE;
    }
    if (MgWait (0x800A, Opcode, 400) && mMgMsgLen >= 12 + 8) {
      UINT32  *W = (UINT32 *)mMgMsg;
      if (W[3] == Prop) {
        *Val = W[4];
        return TRUE;
      }
    }
  }
  return FALSE;
}

// Hand the mini glink over to Windows: after EBS the same SMEM FIFOs can be driven from a user-mode client through rm9io (refs/winpe/battlive.ps1).
// Block at 0xD7FF1400:  +0x00 magic 'GLNK' (written last)  +0x04 SMEM descriptor (item 478) phys  +0x08 Tx FIFO (479) phys  +0x0C Rx FIFO (480) phys
//   +0x10 ADSP->AP read position (mMgPos)  +0x14 free ADSP intents on channel 8 (bit i = intent i)  +0x18 IPCC doorbell address  +0x1C doorbell value  +0x20 ring mask
#define GLNK_ADDR  0xD7FF1400ULL

STATIC VOID
BattGlinkHandoff (VOID)
{
  volatile UINT32  *G = (volatile UINT32 *)(UINTN)GLNK_ADDR;

  G[0] = 0;
  if (mMgD == NULL || mMgTx == NULL || mMgRx == NULL) {
    PL ("GLNK: no mini glink state to hand over\n");
    return;
  }
  MgPoll ();                                   // drain anything the ADSP sent, so mMgPos is current
  G[1] = (UINT32)(UINTN)mMgD;
  G[2] = (UINT32)(UINTN)mMgTx;
  G[3] = (UINT32)(UINTN)mMgRx;
  G[4] = mMgPos;
  G[5] = mMgFree;
  G[6] = (UINT32)(IPCC_B + 0x0C);
  G[7] = 0x30000;
  G[8] = 0x3FFF;
  MemoryFence ();
  G[0] = 0x4B4E4C47U;                          // 'GLNK'
  PL ("GLNK: handoff desc=%08x tx=%08x rx=%08x pos=%u free=0x%x\n", G[1], G[2], G[3], G[4], G[5]);
}

STATIC VOID
BattSnapshot (VOID)
{
  // FIXED slots (the ACPI battery in the DSDT reads them by index): slot i = {key, value}; value 0xFFFFFFFF = no reply.  Order must match refs/acpi/add_battery.py.
  STATIC CONST UINT32  Q[][2] = {
    { 0x30, 0x0 }, { 0x30, 0x1 }, { 0x30, 0x2 }, { 0x30, 0x4 }, { 0x30, 0x7 }, { 0x30, 0x9 }, { 0x30, 0xC }, { 0x30, 0xD }, { 0x30, 0xE }, { 0x30, 0xF },
    { 0x30, 0x10 }, { 0x30, 0x11 }, { 0x30, 0x13 }, { 0x30, 0x1B }, { 0x32, 0x0 }, { 0x32, 0x2 }, { 0x32, 0x4 },
  };
  volatile UINT32  *Out = (volatile UINT32 *)(UINTN)BATT_MAGIC_ADDR;
  UINT32           I, N = 0, V;

  Out[0] = 0;
  for (I = 0; I < ARRAY_SIZE (Q); I++) {
    Out[2 + 2 * I]     = (Q[I][0] << 16) | Q[I][1];
    Out[2 + 2 * I + 1] = 0xFFFFFFFFU;
    if (BattProp (Q[I][0], Q[I][1], &V)) {
      Out[2 + 2 * I + 1] = V;
      N++;
      PL ("BATT: op=0x%x prop=0x%x value=%u (0x%x)\n", Q[I][0], Q[I][1], V, V);
    } else {
      PL ("BATT: op=0x%x prop=0x%x no reply\n", Q[I][0], Q[I][1]);
    }
  }
  Out[1] = ARRAY_SIZE (Q);
  Out[0] = 0x54544142U;   // 'BATT' last: the block is valid only when the magic is there
  PL ("BATT: snapshot done, %u of %u values at 0x%lx\n", N, (UINT32)ARRAY_SIZE (Q), (UINT64)BATT_MAGIC_ADDR);
  BattGlinkHandoff ();
}

STATIC VOID
RtrUcsiInitOnly (VOID)
{
  UINT8   B[48];
  UINT32  Pan[4];

  if (mIpccTimer != NULL) {
    gBS->SetTimer (mIpccTimer, TimerCancel, 0);
  }
  gBS->Stall (200000);
  if (!MgInit ()) {
    PL ("UCSI.INIT: mini glink init failed\n");
    return;
  }
  Pan[0] = 0x800C; Pan[1] = 1; Pan[2] = 0x15; Pan[3] = 1;
  MgSend (Pan, 16);
  gBS->Stall (200000);
  if (!RtrUcsiRead (B)) {
    PL ("UCSI.INIT: first read failed\n");
    return;
  }
  RtrUcsiShow ("init-read", B);
  RtrUcsiCmd ("init-ppm-reset", 0x01, B);
  RtrUcsiCmd ("init-notif-en", 0x05 | (0x8001ULL << 16), B);
  RtrUcsiCmd ("init-conn1-status", 0x12 | (1ULL << 16), B);
  BattSnapshot ();
}

STATIC VOID
UcsiCmd (UINT64 Base, CONST CHAR8 *Tag, UINT64 Command)
{
  MC_PG_SEND  Send = (MC_PG_SEND)(UINTN)(Base + 0x42A0);
  UINT8       *Buf = (UINT8 *)(UINTN)(Base + 0xA258);
  UINT8       Req[64];
  UINTN       R;

  // write buffer with the command in CONTROL (offset 8)
  ZeroMem (Req, sizeof (Req));
  ((UINT32 *)Req)[0] = 0x800B;
  ((UINT32 *)Req)[1] = 1;
  ((UINT32 *)Req)[2] = 0x12;
  CopyMem (Req + 12 + 8, &Command, 8);
  R = Send (0, Req, 64);
  PL ("UCSI %a: WRITE_BUF cmd=%016lx -> 0x%lx ack=%u/%u\n", Tag, Command, (UINT64)R, *(volatile UINT8 *)(UINTN)(Base + 0xA2A8), *(volatile UINT8 *)(UINTN)(Base + 0xA2A9));
  gBS->Stall (500000);
  // read it back
  SetMem (Buf, 48, 0xEE);
  ZeroMem (Req, sizeof (Req));
  ((UINT32 *)Req)[0] = 0x800B;
  ((UINT32 *)Req)[1] = 1;
  ((UINT32 *)Req)[2] = 0x11;
  R = Send (0, Req, 12);
  PL ("UCSI %a: READ_BUF -> 0x%lx\n", Tag, (UINT64)R);
  GlinkFifoDump (Tag);
  UcsiDump (Tag, Buf);
}

STATIC VOID
UcsiProbe (UINT64 *P)
{
  UINT64  Base = (UINT64)(UINTN)P - 0xA0B8;

  PL ("UCSI probe: PmicGlinkDxe image base 0x%lx\n", Base);
  if (SelfFileExists (L"\\RTR.TXT")) {
    Smp2pPublish ();
    gBS->Stall (1000000);
    Smp2pDump ("after-publish");
    RtrOpen (Base, "IPCRTR");
  }
  {
    UINT8       *Buf0 = (UINT8 *)(UINTN)(Base + 0xA258);
    UINT8       Rq[12];
    UINT32      T;
    MC_PG_SEND  Snd = (MC_PG_SEND)(UINTN)(Base + 0x42A0);

    for (T = 0; T < 10; T++) {
      SetMem (Buf0, 48, 0xEE);
      ZeroMem (Rq, sizeof (Rq));
      ((UINT32 *)Rq)[0] = 0x800B;
      ((UINT32 *)Rq)[1] = 1;
      ((UINT32 *)Rq)[2] = 0x11;
      Snd (0, Rq, 12);
      if (Buf0[0] != 0xEE || Buf0[1] != 0xEE) {
        PL ("UCSI service answered at attempt %u: ver=%04x cci=%08x\n", T, *(UINT16 *)Buf0, *(UINT32 *)(Buf0 + 4));
        break;
      }
      gBS->Stall (1000000);
    }
    if (T == 10) {
      PL ("UCSI service never answered (30 tries)\n");
    }
  }
  if (mIpccTimer != NULL && !SelfFileExists (L"\\PMICRAW.TXT")) {
    gBS->SetTimer (mIpccTimer, TimerCancel, 0);   // keep GlinkDxe from consuming the ADSP reply
  }
  mPgBase = Base;
  if (SelfFileExists (L"\\PMICRAW.TXT")) {
    RtrUcsiSession ();
    return;
    {
      UINT32  K, Lim = mRxLogLen < 0x2400 ? mRxLogLen : 0x2400;
      PL ("RXSTREAM total=%u bytes' + BS + 'n", mRxLogLen);
      for (K = 0; K < Lim; K += 32) {
        UINT32  *W = (UINT32 *)(mRxLog + K);
        PL ("RXS %04x: %08x %08x %08x %08x %08x %08x %08x %08x' + BS + 'n", K, W[0], W[1], W[2], W[3], W[4], W[5], W[6], W[7]);
      }
    }
    {
      UINT32  Hi;
      for (Hi = 0; Hi < 0x180; Hi += 8) {
        PL ("PGDATA +%x = %lx\n", 0xA370 + Hi, *(UINT64 *)(UINTN)(Base + 0xA370 + Hi));
      }
      // names of the two glink channel structures
      {
        UINT64  H1 = *(UINT64 *)(UINTN)(Base + 0xA378);
        UINT64  H2 = *(UINT64 *)(UINTN)(Base + 0xA428);
        PL ("PGDATA H1=%lx H2=%lx\n", H1, H2);
        {
          UINT32  Q;
          PL ("H1:");
          for (Q = 0; Q < 20; Q++) {
            PL (" %lx", *(UINT64 *)(UINTN)(H1 + Q * 8));
          }
          PL ("\nH2:");
          for (Q = 0; Q < 20; Q++) {
            PL (" %lx", *(UINT64 *)(UINTN)(H2 + Q * 8));
          }
          PL ("\n");
        }
        {
          UINT64  Pa;
          for (Pa = 0xCD800000ULL; Pa < 0xCE400000ULL; Pa += 8) {
            if (*(UINT64 *)(UINTN)Pa == 0x5254525F43494D50ULL) {   // "PMIC_RTR"
              UINT32  Q2;
              UINT64  Pre = *(UINT64 *)(UINTN)(Pa - 8);
              if (Pre > 0xC0000000ULL && Pre < 0xE0000000ULL && *(UINT64 *)(UINTN)(Pa + 0x20) == 0x800000008ULL) {
                mRtrHandle = Pa - 8;
              }
              PL ("RTRNAME at %lx:", Pa);
              for (Q2 = 0; Q2 < 14; Q2++) {
                PL (" %lx", *(UINT64 *)(UINTN)(Pa - 8 + Q2 * 8));
              }
              PL ("\n");
            }
          }
        }
      }
    }
    PL ("RTR handle = %lx\n", mRtrHandle);
    mDbgOwner = 0x800B;
    PmicDbgCall (Base, "rtr-ucsi-read", 0x11, 0, 0, 0, 0, 1500, 1);
    mDbgOwner = 0x800C;
    PmicDbgCall (Base, "rtr-altmode-pan", 0x15, 1, 0, 0, 0, 1500, 1);
    mDbgOwner = 0x800A;
    PmicDbgCall (Base, "ulog-set", 0x19, 0, 0xFFFFFFFF, 0xFFFFFFFF, 0, 1200, 0xA378);
    PmicDbgCall (Base, "ulog-0x18a", 0x18, 0x2000, 0, 0, 0, 2500, 0xA378);
    PmicDbgCall (Base, "ulog-0x18b", 0x18, 0x2000, 0, 0, 0, 2500, 0xA378);
    gBS->Stall (5000000);
    PmicDbgCall (Base, "ulog-0x18c", 0x18, 0x2000, 0, 0, 0, 2500, 0xA378);
    gBS->Stall (5000000);
    PmicDbgCall (Base, "ulog-0x18d", 0x18, 0x2000, 0, 0, 0, 2500, 0xA378);
    mDbgOwner = 0x800F;
    PmicDbgCall (Base, "raw-1504", 0x37, 0, 7, 0x1504, 2, 600, 0xA378);
    PmicDbgCall (Base, "raw-1104", 0x37, 0, 7, 0x1104, 2, 600, 0xA378);
    PmicDbgCall (Base, "raw-1304", 0x37, 0, 7, 0x1304, 2, 600, 0xA378);
    PmicDbgCall (Base, "raw-1500", 0x37, 0, 7, 0x1500, 1, 600, 0xA378);
  }
  PmicSurvey ();
  UcsiCmd (Base, "read", 0);
  UcsiCmd (Base, "ppm-reset", 0x01);
  gBS->Stall (1000000);
  UcsiCmd (Base, "notif-en", 0x05 | (0xFFFFULL << 16) | (1ULL << 8));
  UcsiCmd (Base, "get-cap", 0x06);
  UcsiCmd (Base, "conn1-status", 0x12 | (1ULL << 16));
  if (SelfFileExists (L"\\UCSIHOST.TXT")) {
    UcsiCmd (Base, "set-ccom-rp", 0x08 | (1ULL << 16) | (1ULL << 23));
    gBS->Stall (2000000);
    UcsiCmd (Base, "conn1-status-after", 0x12 | (1ULL << 16));
  }
  {
    UINT32  Sz2, K;
    UINT8   *F = SmemItem (2, 479, &Sz2);
    UINT32  *D2 = (UINT32 *)SmemItem (2, 478, &Sz2);
    if (F != NULL && D2 != NULL) {
      UINT32  Head = D2[1];
      PL ("GLINK tx fifo (item 479) 0..0x%x:\n", Head);
      for (K = 0; K < Head && K < 0x1400; K += 32) {
        if (K >= 0x400 && K < 0x1000) {
          continue;
        }
        UINT32  *W = (UINT32 *)(F + K);
        PL ("  %04x: %08x %08x %08x %08x %08x %08x %08x %08x\n", K, W[0], W[1], W[2], W[3], W[4], W[5], W[6], W[7]);
      }
    }
    {
      UINT32  Sz3, K;
      UINT8   *R = SmemItem (2, 480, &Sz3);
      if (R != NULL && D2 != NULL) {
        UINT32  RHead = D2[3];
        PL ("GLINK rx fifo (item 480) 0..0x%x:\n", RHead);
        for (K = 0; K < RHead && K < 0x800; K += 32) {
          UINT32  *W = (UINT32 *)(R + K);
          PL ("  r%04x: %08x %08x %08x %08x %08x %08x %08x %08x\n", K, W[0], W[1], W[2], W[3], W[4], W[5], W[6], W[7]);
        }
      }
    }
  }
  Smp2pDump ("end");
  IpccIsrReport ("end");
  SmemDump ("end");
  IpccDxeDump ();
  IpccCfgScan ();
}

// IPCC (ADSP/AOP -> AP doorbells) interrupt service: GIC INTID 261.  Nobody registers a handler for it (IPCCDxe does not), so with the ADSP running the level interrupt storms ("Spurious GIC interrupt: 0x105"
// forever = phone hangs).  RamDebugGuard parks it with a quarantine handler that disables the source.  Replace that by a handler that CLEARS the pending signals (RECV_ID -> RECV_SIGNAL_CLEAR) and counts them;
// it disables the source itself if it runs away.
STATIC EFI_HARDWARE_INTERRUPT_PROTOCOL  *mIpccHw;
STATIC volatile UINT32                  mIpccCalls, mIpccSignals;
STATIC volatile UINT32                  mIpccIds[16];

STATIC VOID
EFIAPI
IpccIsr (HARDWARE_INTERRUPT_SOURCE Source, EFI_SYSTEM_CONTEXT Ctx)
{
  UINT32  I, Id;

  mIpccCalls++;
  for (I = 0; I < 64; I++) {
    Id = MMR (IPCC_B + 0x10);
    if (Id == 0xFFFFFFFFU) {
      break;
    }
    MMW (IPCC_B + 0x1C, Id);
    if (mIpccSignals < 16) {
      mIpccIds[mIpccSignals] = Id;
    }
    mIpccSignals++;
  }
  if (mIpccCalls > 20000) {
    mIpccHw->DisableInterruptSource (mIpccHw, Source);
  }
}

STATIC VOID
IpccIsrInstall (VOID)
{
  EFI_STATUS  St1, St2;
  BOOLEAN     IntState;

  if (EFI_ERROR (gBS->LocateProtocol (&gHardwareInterruptProtocolGuid, NULL, (VOID **)&mIpccHw))) {
    PL ("IPCC isr: no hardware interrupt protocol\n");
    return;
  }
  PcEnsureMmio (IPCC_B, 0x1000, "IPCC");
  PL ("IPCC isr: RECV_ID before = 0x%08x\n", MMR (IPCC_B + 0x10));
  IntState = ArmGetInterruptState ();
  ArmDisableInterrupts ();
  St1 = mIpccHw->RegisterInterruptSource (mIpccHw, 261, NULL);       // drop RamDebugGuard's quarantine handler (also disables the source)
  St2 = mIpccHw->RegisterInterruptSource (mIpccHw, 261, IpccIsr);    // enables the source
  if (IntState) {
    ArmEnableInterrupts ();
  }
  PL ("IPCC isr: unregister quarantine -> %r, register own handler -> %r\n", St1, St2);
}

STATIC VOID
IpccIsrReport (CONST CHAR8 *Tag)
{
  UINT32  I, N = mIpccSignals < 16 ? mIpccSignals : 16;

  PL ("IPCC isr[%a]: calls=%u signals=%u ids:\n", Tag, mIpccCalls, mIpccSignals);
  for (I = 0; I < N; I++) {
    PL ("  id[%u]=0x%08x (client %u signal %u)\n", I, mIpccIds[I], mIpccIds[I] >> 16, mIpccIds[I] & 0xFFFF);
  }
}

// IPCCDxe runtime structures (image base 0xD213D000 in the current layout): the ISR is image+0x2A9C(cfg); per-protocol entries (32 B) at image+0x7670.
STATIC VOID
IpccDxeDump (VOID)
{
  UINT64  B = 0xD213D000ULL;
  UINT32  I, J;

  if (*(UINT16 *)(UINTN)B != 0x5A4D) {
    PL ("IPCCDxe dump: no MZ at 0x%lx\n", B);
    return;
  }
  for (I = 0; I < 8; I++) {
    UINT64  *E = (UINT64 *)(UINTN)(B + 0x7670 + 0x20 * I);
    PL ("IPCCDxe entry[%u]: %016lx %016lx %016lx %016lx\n", I, E[0], E[1], E[2], E[3]);
    for (J = 0; J < 4; J++) {
      UINT64  V = E[J];
      if (V > 0x80000000ULL && V < 0x100000000ULL && (V & 7) == 0) {
        UINT64  *Q = (UINT64 *)(UINTN)V;
        PL ("  e[%u][%u]->%lx: %016lx %016lx %016lx %016lx %016lx %016lx\n", I, J, V, Q[0], Q[1], Q[2], Q[3], Q[4], Q[5]);
      }
    }
  }
}

// find IPCCDxe's per-instance cfg (ISR argument): u64 at +0x10 is the register base (inside the IPCC window 0x400000-0x410000)
STATIC VOID
IpccCfgScan (VOID)
{
  UINT64  P, Hits = 0;
  UINT32  I;

  for (P = 0xCF000000ULL; P < 0xD2A00000ULL && Hits < 12; P += 8) {
    UINT64  V = *(UINT64 *)(UINTN)(P + 0x10);
    UINT16  Id = *(UINT16 *)(UINTN)(P + 6);
    if (V >= 0x400000ULL && V < 0x410000ULL && (Id == 229 || Id == 261 || Id == 0x105 || Id == 0xE5)) {
      PL ("IPCC cfg candidate @%lx (id16@+6=%u):\n", P, Id);
      for (I = 0; I < 8; I++) {
        PL ("   +%02x: %016lx\n", I * 8, *(UINT64 *)(UINTN)(P + I * 8));
      }
      {
        UINT64  Tbl = *(UINT64 *)(UINTN)(P + 0x18);
        UINT32  C;
        for (C = 0; C < 8; C++) {
          UINT64  *T = (UINT64 *)(UINTN)(Tbl + 16 * C);
          if (T[0] != 0) {
            UINT64  *Cb = (UINT64 *)(UINTN)T[0];
            PL ("   client %u -> %lx: %016lx %016lx %016lx %016lx %016lx\n", C, T[0], Cb[0], Cb[1], Cb[2], Cb[3], Cb[4]);
          }
        }
      }
      Hits++;
    }
  }
  PL ("IPCC cfg scan done, hits=%lu\n", Hits);
}

// Poll IPCCDxe's own interrupt routine (image+0x2A9C(cfg)) from a periodic timer instead of the IRQ (nobody could register it: quarantine / DAL IST): it dispatches the ADSP's SMP2P / glink doorbells
// to Smp2pDxe / GlinkDxe.
STATIC UINT64   mIpccCfg;
STATIC EFI_EVENT mIpccTimer;
STATIC UINT64   mIpccDxeBase = 0xD213D000ULL;
STATIC BOOLEAN  mIpccPollBusy;

STATIC UINT32   mIpccPollCalls;

STATIC UINT64
IpccFindCfg (VOID)
{
  UINT64  P, Best = 0;

  for (P = 0xCF000000ULL; P < 0xD2A00000ULL; P += 8) {
    UINT64  V = *(UINT64 *)(UINTN)(P + 0x10);
    UINT16  Id = *(UINT16 *)(UINTN)(P + 6);
    if (V == 0x406000ULL && Id == 261) {
      UINT64  Tbl = *(UINT64 *)(UINTN)(P + 0x18);
      if (Tbl > 0x80000000ULL && Tbl < 0x100000000ULL) {
        UINT64  *T = (UINT64 *)(UINTN)(Tbl + 16 * 3);
        PL ("IPCC cfg @%lx tbl=%lx client3 head=%lx\n", P, Tbl, T[0]);
        if (T[0] != 0 || Best == 0) {
          Best = P;
        }
      }
    }
  }
  return Best;
}

STATIC VOID
EFIAPI
IpccPollCb (IN EFI_EVENT Ev, IN VOID *Ctx)
{
  typedef VOID (EFIAPI *ISR_FN) (VOID *);

  if (mIpccPollBusy || mIpccCfg == 0) {
    return;
  }
  mIpccPollBusy = TRUE;
  mIpccPollCalls++;
  if (mRxSnapOn) {   // copy new APPS<-ADSP FIFO bytes before GlinkDxe consumes (zeroes) them
    UINT32  Sz0;
    if (mRxDesc == NULL || mRxFifo == NULL) {
      mRxDesc = (UINT32 *)SmemItem (2, 478, &Sz0);
      mRxFifo = SmemItem (2, 480, &Sz0);
      mRxLast = (mRxDesc != NULL && mRxFifo != NULL) ? mRxDesc[2] : 0;
      if (mRxDesc == NULL || mRxFifo == NULL) {
        mRxDesc = NULL;
        mRxFifo = NULL;
      }
    }
    if (mRxDesc != NULL && mRxFifo != NULL) {
      UINT32  Hd = mRxDesc[3];
      while (mRxLast != Hd && mRxLogLen < sizeof (mRxLog)) {
        mRxLog[mRxLogLen++] = mRxFifo[mRxLast % 0x4000];
        mRxLast = (mRxLast + 1) % 0x4000;
      }
    }
  }
  ((ISR_FN)(UINTN)(mIpccDxeBase + 0x2A9C)) ((VOID *)(UINTN)mIpccCfg);
  mIpccPollBusy = FALSE;
}

STATIC VOID
IpccPollStart (VOID)
{
  EFI_EVENT   Ev;
  EFI_STATUS  St;

  if (*(UINT16 *)(UINTN)mIpccDxeBase != 0x5A4D) {
    PL ("IPCC poll: IPCCDxe not at 0x%lx\n", mIpccDxeBase);
    return;
  }
  mIpccCfg = IpccFindCfg ();
  PL ("IPCC poll: using cfg %lx\n", mIpccCfg);
  if (mIpccCfg == 0) {
    return;
  }
  St = gBS->CreateEvent (EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, IpccPollCb, NULL, &Ev);
  mIpccTimer = Ev;
  mRxSnapOn = TRUE;
  if (!EFI_ERROR (St)) {
    St = gBS->SetTimer (Ev, TimerPeriodic, 100000);
  }
  PL ("IPCC poll: timer -> %r\n", St);
}

// SMEM overview (read-only): global TOC allocations of items 400..500 and the private partitions (ptable at base+size-4K), to see which smp2p / glink items exist
STATIC VOID
SmemDump (CONST CHAR8 *Tag)
{
  UINT64  B = 0x81D00000ULL, Sz = 0x200000ULL;
  UINT32  I, N;
  UINT8   *Pt = (UINT8 *)(UINTN)(B + Sz - 4096);

  {
    UINT32  K;
    for (K = 0; K < 0x100; K += 0x20) {
      UINT32  *W = (UINT32 *)(UINTN)(B + K);
      PL ("SMEM[%a] +0x%03x: %08x %08x %08x %08x %08x %08x %08x %08x\n", Tag, K, W[0], W[1], W[2], W[3], W[4], W[5], W[6], W[7]);
    }
  }
  PL ("SMEM[%a] ptable magic=%08x version=%u entries=%u\n", Tag, *(UINT32 *)Pt, *(UINT32 *)(Pt + 4), *(UINT32 *)(Pt + 8));
  N = *(UINT32 *)(Pt + 8);
  for (I = 0; I < N && I < 32; I++) {
    UINT8   *E = Pt + 32 + 48 * I;
    UINT32  Off = *(UINT32 *)(E + 0), Size = *(UINT32 *)(E + 4);
    UINT16  H0 = *(UINT16 *)(E + 12), H1 = *(UINT16 *)(E + 14);
    UINT8   *H;
    UINT8   *Ent;
    UINT32  Free, Cnt = 0;

    PL ("SMEM[%a] part%u: hosts %u<->%u offset=0x%x size=0x%x\n", Tag, I, H0, H1, Off, Size);
    if (Size == 0 || Off == 0 || (H0 != 0 && H1 != 0 && H0 != 0xFFFE)) {
      continue;
    }
    H = (UINT8 *)(UINTN)(B + Off);
    Free = *(UINT32 *)(H + 8);
    PL ("   $PRT magic=%08x host %u/%u size=0x%x free_uncached=0x%x\n", *(UINT32 *)H, *(UINT16 *)(H + 4), *(UINT16 *)(H + 6), *(UINT32 *)(H + 8 - 4 + 4 - 4 + 4), Free);
    Ent = H + 32;
    while (Ent < H + Free && Cnt < 40) {
      UINT16  Canary = *(UINT16 *)Ent, Item = *(UINT16 *)(Ent + 2);
      UINT32  ESize = *(UINT32 *)(Ent + 4);
      UINT16  PadData = *(UINT16 *)(Ent + 8), PadHdr = *(UINT16 *)(Ent + 10);
      if (Canary != 0xA5A5) {
        PL ("   bad canary %04x at +0x%x\n", Canary, (UINT32)(Ent - H));
        break;
      }
      PL ("   item %u size=%u (pad %u)\n", Item, ESize, PadData);
      Ent += 16 + PadHdr + ESize;
      Cnt++;
    }
  }
  {
    UINT8   *G = (UINT8 *)(UINTN)B;
    UINT32  Item;
    for (Item = 400; Item < 500; Item++) {
      UINT32  *T = (UINT32 *)(G + 0x10 + 4 * 32 + 16 + 4 * 4 + 0);   // placeholder, replaced below
      (VOID)T;
    }
    // smem_header: proc_comm[4] (16 B each) = 64, version[32] = 128, initialized, free_offset, available, reserved = 16 -> toc at 0xD0, entries 16 B
    for (Item = 400; Item < 500; Item++) {
      UINT32  *T = (UINT32 *)(G + 0xD0 + 16 * Item);
      if (T[0] != 0) {
        PL ("SMEM[%a] global item %u: offset=0x%x size=%u\n", Tag, Item, T[1], T[2]);
      }
    }
  }
}

// APPS<->ADSP SMEM partition (hosts 0 and 2): locate items by walking the private entries, then show the glink-native descriptor (item 478) and the two FIFOs (479 / 480)
STATIC UINT8 *
SmemItem (UINT16 Host1, UINT16 Item, UINT32 *OutSize)
{
  UINT64  B = 0x81D00000ULL, Sz = 0x200000ULL;
  UINT8   *Pt = (UINT8 *)(UINTN)(B + Sz - 4096);
  UINT32  I, N = *(UINT32 *)(Pt + 8);

  for (I = 0; I < N && I < 32; I++) {
    UINT8   *E = Pt + 32 + 48 * I;
    UINT32  Off = *(UINT32 *)(E + 0), Size = *(UINT32 *)(E + 4);
    UINT16  H0 = *(UINT16 *)(E + 12), H1 = *(UINT16 *)(E + 14);
    if (Off != 0 && Size != 0 && H0 == 0 && H1 == Host1) {
      UINT8  *H = (UINT8 *)(UINTN)(B + Off);
      UINT32 Free = *(UINT32 *)(H + 8);
      UINT8  *Ent = H + 32;
      while (Ent < H + Free) {
        UINT16  Canary = *(UINT16 *)Ent, It = *(UINT16 *)(Ent + 2);
        UINT32  ESize = *(UINT32 *)(Ent + 4);
        UINT16  PadHdr = *(UINT16 *)(Ent + 10);
        if (Canary != 0xA5A5) {
          break;
        }
        if (It == Item) {
          if (OutSize != NULL) {
            *OutSize = ESize;
          }
          return Ent + 16 + PadHdr;
        }
        Ent += 16 + PadHdr + ESize;
      }
    }
  }
  return NULL;
}

STATIC VOID
GlinkFifoDump (CONST CHAR8 *Tag)
{
  UINT32  Sz;
  UINT32  *D = (UINT32 *)SmemItem (2, 478, &Sz);
  UINT8   *F0 = SmemItem (2, 479, &Sz);
  UINT8   *F1 = SmemItem (2, 480, &Sz);
  UINT32  I;

  if (D == NULL) {
    PL ("GLINKFIFO[%a] no descriptor\n", Tag);
    return;
  }
  PL ("GLINKFIFO[%a] desc@%p: %08x %08x %08x %08x %08x %08x %08x %08x\n", Tag, D, D[0], D[1], D[2], D[3], D[4], D[5], D[6], D[7]);
  for (I = 0; I < 2; I++) {
    UINT8  *F = I == 0 ? F0 : F1;
    if (F != NULL) {
      UINT32  *W = (UINT32 *)F;
      PL ("GLINKFIFO[%a] fifo%u@%p: %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x\n", Tag, I, F, W[0], W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11]);
    }
  }
}

// PMIC register access through the ADSP (pmic_glink_debug protocol, reverse engineered from pmic-glink-debug.ko): owner 0x800F, type 1;
//   read : opcode 0x37, {bus, sid, addr, len}  -> response opcode 0x37, 0x11C bytes: hdr(12) bus sid addr len(status) data[0x100]
//   write: opcode 0x38, {bus, sid, addr, data} -> response opcode 0x38, 0x10 bytes: hdr(12) status
// Sent with the glink-tx of PmicGlinkDxe's second channel (PMIC_LOGS_ADSP_APPS, handle at image+0xA428); the reply is read straight out of the APPS<-ADSP FIFO (item 480) without consuming it.
typedef UINTN (EFIAPI *MC_GTX) (VOID *Handle, VOID *Priv, VOID *Data, UINTN Size, UINT32 Flags, UINT32 *Out);

STATIC VOID
PmicDbgCall (UINT64 Base, CONST CHAR8 *Tag, UINT32 Opcode, UINT32 A, UINT32 B, UINT32 C, UINT32 D, UINT32 RxWaitMs, UINT32 HandleOff)
{
  UINT64   *GlinkProto = (UINT64 *)(UINTN)(*(UINT64 *)(UINTN)(Base + 0xA370));
  VOID     *Handle = HandleOff == 1 ? (VOID *)(UINTN)mRtrHandle : (VOID *)(UINTN)(*(UINT64 *)(UINTN)(Base + HandleOff));
  UINT32   Msg[8], Out = 0, Start, I, Idle;
  UINTN    R;

  Msg[7] = 0;
  Msg[0] = mDbgOwner; Msg[1] = 1; Msg[2] = Opcode; Msg[3] = A; Msg[4] = B; Msg[5] = C; Msg[6] = D;
  if (Handle == NULL || GlinkProto == NULL || mIpccTimer == NULL) {
    PL ("PMICDBG %a: missing handle/proto/timer (%p %p %p)\n", Tag, Handle, GlinkProto, mIpccTimer);
    return;
  }
  if (!mRxSnapOn) {
    mRxSnapOn = TRUE;
    gBS->SetTimer (mIpccTimer, TimerPeriodic, 20000);   // 2 ms poll: GlinkDxe keeps running, the callback snapshots the FIFO first
    gBS->Stall (300000);
  }
  Start = mRxLogLen;
  R = ((MC_GTX)(UINTN)GlinkProto[0x28 / 8]) (Handle, NULL, Msg, Opcode == 0x19 ? 32 : 28, 0, &Out);
  PL ("PMICDBG %a: tx op=0x%x A=%x B=%x C=%x D=%x -> 0x%lx out=%d\n", Tag, Opcode, A, B, C, D, (UINT64)R, (INT32)Out);
  Idle = 0;
  for (I = 0; I < RxWaitMs && Idle < 300; I++) {   // done once the stream has been quiet for 300 ms
    UINT32  Before = mRxLogLen;
    gBS->Stall (1000);
    Idle = (mRxLogLen != Before || mRxLogLen == Start) ? 0 : Idle + 1;
  }
  PL ("PMICDBG %a: captured %u bytes\n", Tag, mRxLogLen - Start);
  for (I = Start & ~0x1FU; I < mRxLogLen && I < Start + 0x6000; I += 32) {
    UINT32  *W = (UINT32 *)(mRxLog + I);
    PL ("   rx %04x: %08x %08x %08x %08x %08x %08x %08x %08x\n", I, W[0], W[1], W[2], W[3], W[4], W[5], W[6], W[7]);
  }
}

// PMIC register read/write through the ADSP (owner 0x800F debug service) on the PMIC_RTR channel (handle image+0xA378).  Reply: glink TX_DATA(cmd 9, hdr 16 B) + hdr(12) bus sid addr len data[]
// (read, opcode 0x37) or hdr(12) status (write, opcode 0x38).  The reply is copied out of the APPS<-ADSP FIFO (item 480) before GlinkDxe's poll consumes it.
STATIC INTN
PmicDbg (UINT32 Opcode, UINT32 Sid, UINT32 Addr, UINT32 Arg, UINT8 *Data, UINT32 *Len)
{
  UINT64   *GlinkProto = (UINT64 *)(UINTN)(*(UINT64 *)(UINTN)(mPgBase + 0xA370));
  VOID     *Handle = (VOID *)(UINTN)(*(UINT64 *)(UINTN)(mPgBase + 0xA378));
  UINT32   Sz;
  UINT32   *Desc = (UINT32 *)SmemItem (2, 478, &Sz);
  UINT8    *Rx = SmemItem (2, 480, &Sz);
  UINT32   Msg[7], Out = 0, OldHead, I, Pos, Got = 0;
  UINTN    R;
  UINT32   Pay[0x80], Words = 0;

  Msg[0] = 0x800F; Msg[1] = 1; Msg[2] = Opcode; Msg[3] = 0; Msg[4] = Sid; Msg[5] = Addr; Msg[6] = Arg;
  if (Desc == NULL || Rx == NULL) {
    return -1;
  }
  OldHead = Desc[3];
  R = ((MC_GTX)(UINTN)GlinkProto[0x28 / 8]) (Handle, NULL, Msg, sizeof (Msg), 0, &Out);
  if (R != 0) {
    return -2;
  }
  for (I = 0; I < 500; I++) {
    if (Desc[3] != OldHead) {
      break;
    }
    gBS->Stall (1000);
  }
  gBS->Stall (2000);
  // collect words OldHead..Desc[3]
  for (Pos = OldHead; Pos != Desc[3] && Words < 0x80; Pos = (Pos + 4) & 0x3FFF) {
    Pay[Words++] = *(UINT32 *)(Rx + Pos);
  }
  // find TX_DATA (cmd 9) carrying owner 0x800F
  for (I = 0; I + 8 < Words; I++) {
    if ((Pay[I] & 0xFFFF) == 9 && Pay[I + 4] == 0x800F && Pay[I + 6] == Opcode) {
      if (Opcode == 0x37) {
        UINT32  Rl = Pay[I + 10] > 0x100 ? 0x100 : Pay[I + 10];
        if (Data != NULL) {
          CopyMem (Data, &Pay[I + 11], Rl > 0x100 - 4 ? 0x100 - 4 : Rl);
        }
        if (Len != NULL) {
          *Len = Pay[I + 10];
        }
        Got = 1;
        break;
      } else {
        if (Len != NULL) {
          *Len = Pay[I + 7];
        }
        Got = 1;
        break;
      }
    }
  }
  // let GlinkDxe process (RX_DONE etc.)
  {
    typedef UINTN (EFIAPI *GPOLL) (VOID *, UINT32 *);
    UINT32  X;
    ((GPOLL)(UINTN)GlinkProto[0x80 / 8]) (Handle, &X);
    gBS->Stall (2000);
    ((GPOLL)(UINTN)GlinkProto[0x80 / 8]) (Handle, &X);
  }
  return Got ? 0 : -3;
}

STATIC VOID
PmicSurvey (VOID)
{
  UINT32  Page;
  UINT8   D[4];
  UINT32  L;

  for (Page = 0; Page < 0x30; Page++) {
    SetMem (D, sizeof (D), 0xEE);
    L = 0;
    if (PmicDbg (0x37, 7, Page * 0x100 + 4, 2, D, &L) == 0 && (D[0] != 0 || D[1] != 0)) {
      PL ("PMIC sid7 page 0x%02x00: type=0x%02x subtype=0x%02x (len %u)\n", Page, D[0], D[1], L);
    }
  }
}

// SMP2P items of the APPS<->ADSP pair: 443 = ADSP -> APPS, 429 = APPS -> ADSP.  Layout: magic, version/features, local_pid, remote_pid, total_entries, valid_entries, flags, entries[16]{name[16], value}
STATIC VOID
Smp2pDump (CONST CHAR8 *Tag)
{
  UINT32  Sz, K, E;
  UINT16  Items[2] = { 443, 429 };

  for (K = 0; K < 2; K++) {
    UINT32  *P = (UINT32 *)SmemItem (2, Items[K], &Sz);
    if (P == NULL) {
      PL ("SMP2P[%a] item %u: missing\n", Tag, Items[K]);
      continue;
    }
    PL ("SMP2P[%a] item %u: magic=%08x ver/feat=%08x pids=%08x entries=%08x flags=%08x\n", Tag, Items[K], P[0], P[1], P[2], P[3], P[4]);
    for (E = 0; E < (P[3] >> 16) && E < 16; E++) {
      CHAR8   Name[17];
      UINT32  *Ent = P + 5 + 5 * E;
      UINT32  I;
      for (I = 0; I < 16; I++) {
        UINT8  C = ((UINT8 *)Ent)[I];
        Name[I] = (C >= 0x20 && C < 0x7F) ? (CHAR8)C : '.';
      }
      Name[16] = 0;
      PL ("   %a = 0x%08x\n", Name, Ent[4]);
    }
  }
}

// (1) publish the APPS side of the SMP2P pair (item 429: master-kernel / sleepstate / rdbg) the way Linux does and kick the ADSP (IPCC client 3 / signal 2 = SMP2P)
// (2) open the ADSP's "IPCRTR" glink channel (QRTR = QMI service discovery) with our own callbacks and dump what arrives.
STATIC VOID
Smp2pPublish (VOID)
{
  UINT32  Sz, I;
  UINT32  *P = (UINT32 *)SmemItem (2, 429, &Sz);
  STATIC CONST CHAR8  *Names[3] = { "master-kernel", "sleepstate", "rdbg" };
  STATIC CONST UINT32  Vals[3]  = { 0, 0x1000, 0 };

  if (P == NULL) {
    PL ("SMP2P publish: item 429 missing\n");
    return;
  }
  for (I = 0; I < 3; I++) {
    UINT8   *Ent = (UINT8 *)(P + 5 + 5 * I);
    UINT32  K;
    SetMem (Ent, 16, 0);
    for (K = 0; Names[I][K] != 0; K++) {
      Ent[K] = (UINT8)Names[I][K];
    }
    *(volatile UINT32 *)(Ent + 16) = Vals[I];
  }
  P[3] = (3U << 16) | 0x10;           // valid_entries = 3, total_entries = 16
  MemoryFence ();
  MMW (IPCC_B + 0x0C, (3U << 16) | 2); // kick LPASS / SMP2P
  PL ("SMP2P publish: item 429 now valid_entries=%u, kicked ADSP\n", P[3] >> 16);
}

STATIC UINT32  mRtrCount;
STATIC UINT32  mRtrState = 0xFF;
STATIC UINT32  mRtrLen[32];
STATIC UINT8   mRtrBuf[32][128];
STATIC UINT64  mRtrProto;

STATIC VOID
EFIAPI
RtrRx (VOID *H, VOID *Priv, VOID *PktPriv, CONST VOID *Ptr, UINTN Size, UINTN Used)
{
  typedef UINTN (EFIAPI *RXDONE) (VOID *, CONST VOID *, UINT8, UINT32 *);
  UINT32  St = 0;

  if (mRtrCount < 32) {
    UINTN  N = Size > 128 ? 128 : Size;
    CopyMem (mRtrBuf[mRtrCount], Ptr, N);
    mRtrLen[mRtrCount] = (UINT32)Size;
  }
  mRtrCount++;
  ((RXDONE)(UINTN)((UINT64 *)(UINTN)mRtrProto)[0x40 / 8]) (H, Ptr, 1, &St);
}

STATIC VOID
EFIAPI
RtrState (VOID *H, VOID *Priv, UINT32 State)
{
  typedef UINTN (EFIAPI *QINT) (VOID *, VOID *, UINTN, UINT32 *);
  UINT32  I, St = 0;

  mRtrState = State;
  if (State == 0) {
    for (I = 0; I < 6; I++) {
      ((QINT)(UINTN)((UINT64 *)(UINTN)mRtrProto)[0x38 / 8]) (H, NULL, 0x1000, &St);
    }
  }
}

STATIC VOID
EFIAPI
RtrTxDone (VOID *A, VOID *B, VOID *C, VOID *D, VOID *E)
{
}

STATIC VOID RtrSendHello (UINT64 *Proto, VOID *Handle);
STATIC VOID
RtrSendQmiListener (UINT64 *Proto, VOID *Handle, CONST CHAR8 *Domain, UINT32 Txn, UINT32 Mode)
{
  typedef UINTN (EFIAPI *GTXF) (VOID *, VOID *, VOID *, UINTN, UINT32, UINT32 *);
  UINT8   Buf[128];
  UINT32  *H = (UINT32 *)Buf;
  UINT8   *Q = Buf + 32;
  UINT32  Nl = (UINT32)AsciiStrLen (Domain), L = 0, St = 0, T;
  UINTN   R = 0;

  ZeroMem (Buf, sizeof (Buf));
  Q[0] = 0;                        // ctrl flags: request
  Q[1] = (UINT8)Txn; Q[2] = (UINT8)(Txn >> 8);
  Q[3] = 0x20; Q[4] = 0x00;        // msg id REGISTER_LISTENER_REQ
  // TLV 0x01 enable = 1
  Q[7 + L] = 0x01; Q[8 + L] = 1; Q[9 + L] = 0; Q[10 + L] = 1; L += 4;
  // TLV 0x02 service_name (1-byte length prefix + chars)
  if ((Mode & 1) != 0) {            // no length prefix: TLV value = chars
    Q[7 + L] = 0x02; Q[8 + L] = (UINT8)Nl; Q[9 + L] = 0;
    CopyMem (Q + 10 + L, Domain, Nl);
    L += 3 + Nl;
  } else {
    UINT32  Cn = (Mode & 2) != 0 ? Nl + 1 : Nl;   // include the NUL?
    Q[7 + L] = 0x02; Q[8 + L] = (UINT8)(Cn + 1); Q[9 + L] = 0; Q[10 + L] = (UINT8)Cn;
    CopyMem (Q + 11 + L, Domain, Nl);
    L += 4 + Cn;
  }
  Q[5] = (UINT8)L; Q[6] = (UINT8)(L >> 8);
  H[0] = 1; H[1] = 1;              // QRTR v1, type DATA
  H[2] = 1; H[3] = 0x4000;         // src node 1, our port
  H[4] = 0; H[5] = 7 + L;          // confirm_rx, size
  H[6] = 5; H[7] = 2;              // dst: ADSP node 5, servreg-notifier port 2
  for (T = 0; T < 20; T++) {
    R = ((GTXF)(UINTN)Proto[0x28 / 8]) (Handle, NULL, Buf, 32 + 7 + L, 0, &St);
    if (R == 0) {
      break;
    }
    gBS->Stall (50000);
  }
  PL ("QMI register_listener(%a mode %u txn %u) tx -> 0x%lx st=%d\n", Domain, Mode, Txn, (UINT64)R, (INT32)St);
}

STATIC VOID
RtrSendHello (UINT64 *Proto, VOID *Handle)
{
  typedef UINTN (EFIAPI *GTXF) (VOID *, VOID *, VOID *, UINTN, UINT32, UINT32 *);
  UINT32  Pkt[13];
  UINT32  St = 0, T;
  UINTN   R = 0;

  ZeroMem (Pkt, sizeof (Pkt));
  Pkt[0] = 1;            // version
  Pkt[1] = 2;            // type HELLO
  Pkt[2] = 1;            // src node (APPS = 1 as in Android)
  Pkt[3] = 0xFFFFFFFE;   // src port (control)
  Pkt[4] = 0;            // confirm_rx
  Pkt[5] = 0x14;         // payload size
  Pkt[6] = 0xFFFFFFFF;   // dst node (broadcast)
  Pkt[7] = 0xFFFFFFFE;   // dst port (control)
  Pkt[8] = 2;            // ctrl cmd HELLO
  for (T = 0; T < 20; T++) {
    R = ((GTXF)(UINTN)Proto[0x28 / 8]) (Handle, NULL, Pkt, 52, 0, &St);
    if (R == 0) {
      break;
    }
    gBS->Stall (50000);
  }
  PL ("IPCRTR HELLO tx -> 0x%lx st=%d (try %u)\n", (UINT64)R, (INT32)St, T);
}

STATIC VOID
RtrOpen (UINT64 Base, CONST CHAR8 *NameIn)
{
  typedef UINTN (EFIAPI *GOPEN) (VOID *, VOID **, UINT32 *);
  UINT64  *Proto = (UINT64 *)(UINTN)(*(UINT64 *)(UINTN)(Base + 0xA220));
  UINT8   Cfg[0x90];
  VOID    *Handle = NULL;
  UINT32  St = 0xFFFFFFF5, I;
  UINTN   R;
  UINT32  X;

  mRtrProto = (UINT64)(UINTN)Proto;
  CopyMem (Cfg, (VOID *)(UINTN)(Base + 0xA2E0), sizeof (Cfg));
  *(UINT64 *)(Cfg + 0x10) = (UINT64)(UINTN)NameIn;
  *(UINT64 *)(Cfg + 0x28) = (UINT64)(UINTN)RtrRx;
  *(UINT64 *)(Cfg + 0x40) = (UINT64)(UINTN)RtrTxDone;
  *(UINT64 *)(Cfg + 0x48) = (UINT64)(UINTN)RtrState;
  R = ((GOPEN)(UINTN)Proto[0x18 / 8]) (Cfg, &Handle, &St);
  PL ("IPCRTR open -> 0x%lx status=%d handle=%p\n", (UINT64)R, (INT32)St, Handle);
  for (I = 0; I < 4000 && Handle != NULL; I++) {
    typedef UINTN (EFIAPI *GPOLL) (VOID *, UINT32 *);
    ((GPOLL)(UINTN)Proto[0x80 / 8]) (Handle, &X);
    gBS->Stall (1000);
    if (mRtrCount >= 32) {
      break;
    }
    if (I == 300 && NameIn[0] == 'I') {
      RtrSendHello (Proto, Handle);
    }
    if (I == 900 && NameIn[0] == 'I') {
      RtrSendQmiListener (Proto, Handle, "msm/adsp/root_pd", 11, 1);
      RtrSendQmiListener (Proto, Handle, "msm/adsp/audio_pd", 12, 1);
      RtrSendQmiListener (Proto, Handle, "msm/adsp/sensor_pd", 13, 1);
      RtrSendQmiListener (Proto, Handle, "msm/adsp/charger_pd", 14, 1);
      RtrSendQmiListener (Proto, Handle, "msm/adsp/oem_pd", 15, 1);
      RtrSendQmiListener (Proto, Handle, "msm/adsp/charger_pd", 16, 1);
    }
  }
  PL ("IPCRTR: state=%d rx messages=%u\n", (INT32)mRtrState, mRtrCount);
  for (I = 0; I < mRtrCount && I < 32; I++) {
    UINT32  *W = (UINT32 *)mRtrBuf[I];
    if (W[1] == 1) {
      UINT8  *Qm = (UINT8 *)(W + 8);
      PL ("    QMI flags=%u txn=%u msg=0x%x len=%u tlv0: type=0x%x tlen=%u val=%08x %08x' + bs + 'n", Qm[0], Qm[1] | (Qm[2] << 8), Qm[3] | (Qm[4] << 8), Qm[5] | (Qm[6] << 8), Qm[7], Qm[8] | (Qm[9] << 8), *(UINT32 *)(Qm + 10), *(UINT32 *)(Qm + 14));
    }
    PL ("  rtr[%u] len=%u: type=%u src=%u:%x size=%u dst=%x:%x | %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x\n", I, mRtrLen[I], W[1], W[2], W[3], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16], W[17]);
  }
}

// ADSP.TXT + NOBOOT: load the ADSP the way QcomChargerDxe does (PIL protocol fn1 = ProcessPilImage(CHAR16 *Name), config uefipil.cfg FULL_ADSP + FULL_ADSP_DTB from the modem partition)
typedef UINTN (EFIAPI *MC_PIL_LOAD) (CONST CHAR16 *Name);

STATIC VOID
AdspLoad (VOID)
{
  STATIC EFI_GUID  Guid = { 0x1F4F1DA3, 0x4D8D, 0x4894, { 0xBA, 0x2A, 0x13, 0xD3, 0x20, 0x7F, 0x97, 0x39 } };
  UINT64      *P = NULL;
  EFI_STATUS  St;
  UINTN       R;
  UINT64      T0;

  St = gBS->LocateProtocol (&Guid, NULL, (VOID **)&P);
  PL ("LocateProtocol(PIL) -> %r P=%p revision 0x%lx fn1=%p\n", St, P, P ? P[0] : 0, P ? (VOID *)P[1] : NULL);
  if (EFI_ERROR (St) || P == NULL) {
    return;
  }
  if (SelfFileExists (L"\\OWNISR.TXT")) {
    IpccIsrInstall ();
  }
  T0 = PcNowUs ();
  R = ((MC_PIL_LOAD)P[1]) (L"FULL_ADSP");
  PL ("ProcessPilImage(FULL_ADSP) -> 0x%lx in %lu ms\n", (UINT64)R, (PcNowUs () - T0) / 1000);
  if (R == 0) {
    // Android only brings the AP side of glink up ~0.7 s after the ADSP starts: pmic_glink_init() registers a glink link-state callback ("apss"/"SMEM") that only fires on a later UP transition.
    // If GlinkDxe answers before the charger init registered it, PMIC_RTR_ADSP_APPS is never opened.  So do not service the ADSP for a while.
    IpccPollStart ();
    gBS->Stall (8000000);
    IpccIsrReport ("after-8s");
    SmemDump ("after-8s");
    GlinkFifoDump ("after-8s");
    Smp2pDump ("after-8s");
    PmicGlinkLink ();
    {
      EFI_GUID  Gg = { 0x7429EB07, 0xF2E3, 0x4A6B, { 0xAA, 0x96, 0xC9, 0x09, 0xCD, 0x95, 0x6E, 0xF7 } };
      UINT64    *Pg = NULL;
      if (SelfFileExists (L"\\UCSIINIT.TXT")) {
        RtrUcsiInitOnly ();
      } else if (!EFI_ERROR (gBS->LocateProtocol (&Gg, NULL, (VOID **)&Pg)) && Pg != NULL) {
        UcsiProbe (Pg);
      }
    }
  }
}

// USBPWR.TXT + NOBOOT: Qualcomm's UsbPwrCtrlDxe protocol (reverse engineered, see HANDOVER 0.16): Revision 0x10003 followed by 12 plain functions with NO This pointer:
//   1 GetVbusDetect(port,out) 2 GetVbusSourceOK 3 GetHSUsbChgPortType 4 GetUsbIDStatus 5 GetTypeCPortStatus 6 GetPDStatus(port,out[0x18]) 7 SetSnkMaxInputCurrent(port,mA)
//   8 SetSrcMaxOutputCurrent(port,mA) 9 SetVbusEn(port,en) 10 SetVconnEn(port,en) 11 ? 12 stub.  Read-only unless USBPWR1.TXT exists (then SetVbusEn(0,1) for 3 s).
typedef UINTN (EFIAPI *MC_PWR_FN) (UINTN Port, VOID *Out, VOID *Out2);

STATIC VOID
UsbPwrGetters (CONST CHAR8 *Tag, UINT64 *Fn)
{
  STATIC CONST CHAR8  *Names[] = { "GetVbusDetect", "GetVbusSourceOK", "GetHSUsbChgPortType", "GetUsbIDStatus", "GetTypeCPortStatus", "GetPDStatus" };
  UINT32  Port, I, K;
  UINT32  Buf[16], Buf2[16];
  UINTN   St;

  for (Port = 0; Port < 2; Port++) {
    for (I = 0; I < 6; I++) {
      for (K = 0; K < 16; K++) {
        Buf[K] = 0xA5A5A5A5;
        Buf2[K] = 0xA5A5A5A5;
      }
      St = ((MC_PWR_FN)Fn[I]) (Port, Buf, Buf2);
      PL ("PWR[%a] port%u %a -> 0x%lx out: %08x %08x %08x %08x %08x %08x | %08x %08x\n", Tag, Port, Names[I], (UINT64)St, Buf[0], Buf[1], Buf[2], Buf[3], Buf[4], Buf[5], Buf2[0], Buf2[1]);
    }
  }
}

STATIC VOID
UsbPwrProbe (VOID)
{
  STATIC EFI_GUID  Guid = { 0xE07DF17E, 0xE79E, 0x4150, { 0x93, 0x78, 0x50, 0x62, 0x3A, 0x14, 0x99, 0x4A } };
  UINT64      *P = NULL;
  EFI_STATUS  St;
  UINT32      I;

  PL ("=== UsbPwrCtrl probe\n");
  St = gBS->LocateProtocol (&Guid, NULL, (VOID **)&P);
  PL ("LocateProtocol(UsbPwrCtrl) -> %r P=%p\n", St, P);
  if (EFI_ERROR (St) || P == NULL) {
    return;
  }
  PL ("revision 0x%lx fns:", P[0]);
  for (I = 1; I <= 12; I++) {
    PL (" %p", (VOID *)P[I]);
  }
  PL ("\n");
  UsbPwrGetters ("before", &P[1]);
  if (SelfFileExists (L"\\USBPWR1.TXT")) {
    St = ((MC_PWR_FN)P[9]) (0, (VOID *)1, NULL);
    PL ("SetVbusEn(0,1) -> 0x%lx\n", (UINT64)St);
    gBS->Stall (3000000);
    UsbPwrGetters ("vbus-on", &P[1]);
    St = ((MC_PWR_FN)P[9]) (0, NULL, NULL);
    PL ("SetVbusEn(0,0) -> 0x%lx\n", (UINT64)St);
    UsbPwrGetters ("vbus-off", &P[1]);
  }
}

// ===== polled GENI SPI master on SE4 (qupv3_1, 0xA90000), FIFO mode, written from mainline qcom-geni-se.c / spi-geni-qcom.c (geni_se_init, spi_geni_init, setup_se_xfer, geni_spi_handle_tx/rx).
// Registers (SE base + offset): 0x20 FORCE_DEFAULT 0x24 OUTPUT_CTRL 0x28 CGC_CTRL 0x40 STATUS 0x48 SER_M_CLK_CFG 0x60 CLK_CTRL_RO 0x64 IF_DISABLE_RO 0x68 FW_REVISION_RO (proto = bits 15:8, SPI = 1)
//   0x7c CLK_SEL 0x224 SPI_CPHA 0x22c SPI_LOOPBACK 0x230 SPI_CPOL 0x24c DEMUX_OUTPUT_INV 0x250 DEMUX_SEL 0x254 BYTE_GRAN 0x258 DMA_MODE_EN 0x25c SPI_TRANS_CFG 0x260/0x264 TX_PACKING_CFG0/1
//   0x268 SPI_WORD_LEN 0x26c SPI_TX_TRANS_LEN 0x270 SPI_RX_TRANS_LEN 0x284/0x288 RX_PACKING_CFG0/1 0x600 M_CMD0 0x610 M_IRQ_STATUS 0x614 M_IRQ_EN 0x618 M_IRQ_CLEAR 0x644 S_IRQ_EN 0x648 S_IRQ_CLEAR
//   0x700 TX_FIFO 0x780 RX_FIFO 0x800 TX_FIFO_STATUS 0x804 RX_FIFO_STATUS 0x80c TX_WATERMARK 0x810 RX_WATERMARK 0x814 RX_RFR_WATERMARK 0xc44 DMA_TX_IRQ_CLR 0xd44 DMA_RX_IRQ_CLR
//   0xe18 GSI_EVENT_EN 0xe1c SE_IRQ_EN 0xe24 HW_PARAM_0 (TX FIFO depth bits 21:16, width bits 29:24) 0xe30 DMA_GENERAL_CFG ; wrapper 0xAC0004 = QUP HW version (1.0 => oversampling 2)
#define SE4_B       0x00A90000ULL
#define SE_R(o)   MMR (SE4_B + (o))
#define SE_W(o, v) MMW (SE4_B + (o), (v))

STATIC UINT32  mGeniOvs = 1;

STATIC VOID
GeniSeDump (VOID)
{
  PL ("GENI: fw_rev=0x%08x s_fw_rev=0x%08x status=0x%08x clk_ctrl=0x%08x if_disable=0x%08x hw0=0x%08x hw1=0x%08x qup_ver=0x%08x%a", SE_R (0x68), SE_R (0x6C), SE_R (0x40), SE_R (0x60), SE_R (0x64), SE_R (0xE24), SE_R (0xE28), MMR (0x00AC0004ULL), "\n");
  PL ("GENI: cgc=0x%08x dma_mode=0x%08x m_irq_st=0x%08x m_irq_en=0x%08x txfifo_st=0x%08x rxfifo_st=0x%08x word_len=0x%08x trans_cfg=0x%08x%a", SE_R (0x28), SE_R (0x258), SE_R (0x610), SE_R (0x614), SE_R (0x800), SE_R (0x804), SE_R (0x268), SE_R (0x25C), "\n");
}

STATIC BOOLEAN
GeniSpiInit (IN UINT32 SclkDiv)
{
  UINT32  Proto = (SE_R (0x68) >> 8) & 0xFF, Depth, Ver;

  if (Proto != 1) {
    PL ("GENI: protocol firmware is %u, not SPI (1)%a", Proto, "\n");
    return FALSE;
  }
  Ver = MMR (0x00AC0004ULL);
  mGeniOvs = ((Ver >> 28) == 1 && ((Ver >> 16) & 0xFFF) == 0) ? 2 : 1;
  // geni_se_init(): irq_clear, io_init, io_set_mode
  SE_W (0xE18, 0);
  SE_W (0x618, 0xFFFFFFFF);
  SE_W (0x648, 0xFFFFFFFF);
  SE_W (0xC44, 0xFFFFFFFF);
  SE_W (0xD44, 0xFFFFFFFF);
  SE_W (0xE1C, 0xFFFFFFFF);
  SE_W (0x28, SE_R (0x28) | 0x7F);             // DEFAULT_CGC_EN
  SE_W (0xE30, SE_R (0xE30) | 0xF);            // AHB_SEC_SLV | DMA_AHB_SLV | DMA_TX | DMA_RX clock gating off
  SE_W (0x24, 0x7F);                           // DEFAULT_IO_OUTPUT_CTRL_MSK
  SE_W (0x20, 1);                              // FORCE_DEFAULT
  SE_W (0x258, SE_R (0x258) & ~1U);            // FIFO mode
  SE_W (0xE18, 0);
  Depth = (SE_R (0xE24) >> 16) & 0x3F;
  if (Depth < 4) {
    Depth = 16;
  }
  SE_W (0x810, Depth - 3);                     // RX watermark
  SE_W (0x814, Depth - 2);                     // RX RFR watermark
  SE_W (0x614, SE_R (0x614) | 0x7FC0007F);   // M_COMMON | CMD_DONE | RX/TX watermark, RX last
  SE_W (0x644, SE_R (0x644) | 0x3E | 0x3E00 | 0x3000000);                                                                    // S_COMMON
  // setup_fifo_params() starts from zero
  SE_W (0x22C, 0);
  SE_W (0x250, 0);
  SE_W (0x224, 0);                             // CPHA 0
  SE_W (0x230, 0);                             // CPOL 0
  SE_W (0x24C, 0);
  SE_W (0x25C, SE_R (0x25C) & ~2U);            // no CS toggle
  // spi_setup_word_len(8 bits, 4 words per FIFO entry, MSB first): packing vectors from geni_se_config_packing()
  SE_W (0x260, 0x7F8FE);
  SE_W (0x264, 0xFFEFE);
  SE_W (0x284, 0x7F8FE);
  SE_W (0x288, 0xFFEFE);
  SE_W (0x254, 0);                             // BYTE_GRAN: 4x8
  SE_W (0x268, 8 - 4);                         // word length (bpw - MIN_WORD_LEN)
  // clock: select source 0, divider, enable
  SE_W (0x7C, 0);
  SE_W (0x48, (SclkDiv << 4) | 1U);
  PL ("GENI: init done: depth=%u words, oversampling=%u, sclk=%u Hz%a", Depth, mGeniOvs, (UINT32)(19200000 / (mGeniOvs * SclkDiv)), "\n");
  return TRUE;
}

// SE4 has its FIFO interface disabled (GENI_IF_DISABLE_RO bit0 = 1: the SE is meant for GSI/GPI use), so use the serial engine's own DMA (geni_se_select_dma_mode + geni_se_tx/rx_init_dma, as spi-geni-qcom
// does for transfers with sg lists): buffers are plain physical addresses (UEFI is identity mapped), cache lines are cleaned/invalidated by hand.
STATIC UINT8  mDmaTx[128] __attribute__ ((aligned (64)));
STATIC UINT8  mDmaRx[128] __attribute__ ((aligned (64)));

STATIC VOID
GeniCacheOp (IN VOID *Buf, IN UINT32 Len)
{
  UINT64  A = (UINT64)(UINTN)Buf & ~63ULL, E = (UINT64)(UINTN)Buf + Len;

  for (; A < E; A += 64) {
    __asm__ volatile ("dc civac, %0" : : "r" (A) : "memory");
  }
  __asm__ volatile ("dsb sy" : : : "memory");
}

STATIC BOOLEAN
GeniSpiXfer (IN CONST UINT8 *Tx, OUT UINT8 *Rx, IN UINT32 Len)
{
  UINT32  I, T, Td = 0, Rd = 0, M = 0;

  if (Len == 0 || Len > 64) {
    return FALSE;
  }
  for (I = 0; I < 128; I++) {
    mDmaTx[I] = I < Len ? Tx[I] : 0;
    mDmaRx[I] = 0xEE;
  }
  GeniCacheOp (mDmaTx, 128);
  GeniCacheOp (mDmaRx, 128);
  // geni_se_select_dma_mode(): irq clear, mask the FIFO interrupts, DMA mode on
  SE_W (0xE18, 0);
  SE_W (0x618, 0xFFFFFFFF);
  SE_W (0x648, 0xFFFFFFFF);
  SE_W (0xC44, 0xFFFFFFFF);
  SE_W (0xD44, 0xFFFFFFFF);
  SE_W (0xE1C, 0xFFFFFFFF);
  SE_W (0x614, SE_R (0x614) & ~(0x1U | 0x40000000U | 0x4000000U | 0x8000000U));
  SE_W (0x258, SE_R (0x258) | 1U);
  PL ("XFER: dma mode on\n");
  SE_W (0x26C, Len);
  SE_W (0x270, Len);
  SE_W (0x600, 3U << 27);                                       // SPI_TX_ONLY | SPI_RX_ONLY
  PL ("XFER: cmd issued\n");
  // geni_se_rx_init_dma() then geni_se_tx_init_dma()
  SE_W (0xD4C, 7);
  SE_W (0xD30, (UINT32)(UINTN)mDmaRx);
  SE_W (0xD34, (UINT32)(((UINT64)(UINTN)mDmaRx) >> 32));
  SE_W (0xD38, 0);
  SE_W (0xD3C, Len);
  PL ("XFER: rx dma armed\n");
  SE_W (0xC4C, 7);
  SE_W (0xC30, (UINT32)(UINTN)mDmaTx);
  SE_W (0xC34, (UINT32)(((UINT64)(UINTN)mDmaTx) >> 32));
  SE_W (0xC38, 1);                                              // EOT buffer
  SE_W (0xC3C, Len);
  PL ("XFER: tx dma armed\n");
  for (T = 0; T < 20000; T++) {                                 // ~200 ms
    Td |= SE_R (0xC40);
    Rd |= SE_R (0xD40);
    M |= SE_R (0x610);
    if ((Td & 4) != 0 || (Rd & 4) != 0 || (M & 0x3300003EU) != 0) {
      PL ("GENI: dma error tx=0x%x rx=0x%x m_irq=0x%x%a", Td, Rd, M, "\n");
      break;
    }
    if ((Td & 1) != 0 && (Rd & 1) != 0) {
      break;
    }
    gBS->Stall (10);
  }
  if ((Td & 1) == 0 || (Rd & 1) == 0) {
    PL ("GENI: dma timeout/err: tx_stat=0x%x rx_stat=0x%x m_irq=0x%x status=0x%x tx_len_in=%u rx_len_in=%u%a", Td, Rd, M, SE_R (0x40), SE_R (0xC54), SE_R (0xD54), "\n");
    SE_W (0x604, 4U);                                           // cancel
    gBS->Stall (2000);
    SE_W (0xC58, 1);                                            // TX/RX FSM reset
    SE_W (0xD58, 1);
    gBS->Stall (2000);
    SE_W (0x618, 0xFFFFFFFF);
    SE_W (0xC44, 0xFFFFFFFF);
    SE_W (0xD44, 0xFFFFFFFF);
    return FALSE;
  }
  for (T = 0; T < 1000 && (SE_R (0x610) & 1U) == 0; T++) {      // command done (CS released)
    gBS->Stall (10);
  }
  SE_W (0x618, 0xFFFFFFFF);
  SE_W (0xC44, 0xFFFFFFFF);
  SE_W (0xD44, 0xFFFFFFFF);
  GeniCacheOp (mDmaRx, 128);
  for (I = 0; I < Len; I++) {
    Rx[I] = mDmaRx[I];
  }
  return TRUE;
}

// Goodix BRL-D frames: WRITE = F0 + addr(4, BE) + data; READ = F1 + addr(4, BE) + FF FF FF + dummy, data starts at offset 8 of the rx
STATIC BOOLEAN
GoodixRead (IN UINT32 Addr, OUT UINT8 *Data, IN UINT32 Len)
{
  UINT8   Tx[64], Rx[64];
  UINT32  I;

  if (Len == 0 || Len + 8 > 64) {
    return FALSE;
  }
  SetMem (Tx, sizeof (Tx), 0);
  Tx[0] = 0xF1;
  Tx[1] = (UINT8)(Addr >> 24);
  Tx[2] = (UINT8)(Addr >> 16);
  Tx[3] = (UINT8)(Addr >> 8);
  Tx[4] = (UINT8)Addr;
  Tx[5] = Tx[6] = Tx[7] = 0xFF;
  if (!GeniSpiXfer (Tx, Rx, 8 + Len)) {
    return FALSE;
  }
  for (I = 0; I < Len; I++) {
    Data[I] = Rx[8 + I];
  }
  return TRUE;
}

STATIC BOOLEAN
__attribute__ ((unused))
GoodixWrite (IN UINT32 Addr, IN CONST UINT8 *Data, IN UINT32 Len)
{
  UINT8   Tx[64], Rx[64];
  UINT32  I;

  if (Len + 5 > 64) {
    return FALSE;
  }
  Tx[0] = 0xF0;
  Tx[1] = (UINT8)(Addr >> 24);
  Tx[2] = (UINT8)(Addr >> 16);
  Tx[3] = (UINT8)(Addr >> 8);
  Tx[4] = (UINT8)Addr;
  for (I = 0; I < Len; I++) {
    Tx[5 + I] = Data[I];
  }
  return GeniSpiXfer (Tx, Rx, 5 + Len);
}

// ===== TOUCH.TXT + NOBOOT: Goodix BRL-D (9916R) on SPI via GENI SE4 (qupv3_1 se4, spi@a90000).  Everything here is brought up from scratch because UEFI leaves it off:
//   power : IOVDD enable = TLMM gpio28 (high), AVDD = RPMh ldob14 3.2 V (HPM), RESET = gpio161, IRQ = gpio162 (input, falling)
//   pins  : gpio48 = MISO(qup1_se4_l0) gpio49 = MOSI(l1) gpio50 = CLK(l2) gpio51 = CS(l3), function 1, 6 mA (drv field 2), pull-down (as the Android DT)
//   clock : GCC (base 0x100000): AHB gates 0x52008 bits 20/21, SE4 clock gate 0x52008 bit 26 (halt 0x183bc), RCG gcc_qupv3_wrap1_s4_clk_src cmd 0x183c8 (cfg +4, M +8, N +0xc, D +0x10) -> TCXO 19.2 MHz
#define SE4_B       0x00A90000ULL
#define GCC_QUP_EN  (GCC_B + 0x52008)

STATIC BOOLEAN
TouchWaitClear (IN UINT64 Addr, IN UINT32 Mask, IN UINT32 TimeoutUs)
{
  UINT32  T;

  for (T = 0; T < TimeoutUs; T += 10) {
    if ((MMR (Addr) & Mask) == 0) {
      return TRUE;
    }
    gBS->Stall (10);
  }
  return FALSE;
}

STATIC VOID
TouchPowerUp (VOID)
{
  PL ("TOUCH: power-up%a", "\n");
  // pins first, so nothing floats while the supplies come up
  PcGpio (28, 0x200, 1);              // IOVDD enable: GPIO function 0, output driver on, high
  PcGpio (161, 0x200, 0);             // RESET low
  PcGpio (162, 0x3, -1);              // IRQ: input, pull-up
  PcRailHpm ("ldob14", 3200000);      // AVDD 3.2 V
  gBS->Stall (20000);
  PcGpio (161, 0x200, 1);             // release reset
  gBS->Stall (300000);                // IC boot (the Linux driver waits ~100 ms after reset)
  PL ("TOUCH: irq(gpio162)=%u reset(gpio161)=%u iovdd(gpio28)=%u%a", (MMR (TLMM_B + 0x1000ULL * 162 + 4) & 1), (MMR (TLMM_B + 0x1000ULL * 161 + 4) & 1), (MMR (TLMM_B + 0x1000ULL * 28 + 4) & 1), "\n");
}

STATIC VOID
TouchSpiPins (VOID)
{
  UINT32  N;

  for (N = 48; N <= 51; N++) {
    MMW (TLMM_B + 0x1000ULL * N, (2U << 6) | (1U << 2) | 1U);   // drive 6 mA, function 1 (qup1_se4), pull-down
    PL ("TOUCH: gpio%u cfg=0x%x%a", N, MMR (TLMM_B + 0x1000ULL * N), "\n");
  }
}

STATIC BOOLEAN
TouchClocks (VOID)
{
  UINT64  Cmd = GCC_B + 0x183C8;
  BOOLEAN Ok;

  PL ("TOUCH: gcc before: qup_en=0x%08x s4 halt=0x%08x rcg cmd=0x%08x cfg=0x%08x%a", MMR (GCC_QUP_EN), MMR (GCC_B + 0x183BC), MMR (Cmd), MMR (Cmd + 4), "\n");
  MMW (GCC_QUP_EN, MMR (GCC_QUP_EN) | (1U << 20) | (1U << 21));       // wrapper 1 AHB clocks
  MMW (Cmd + 4, 0);                                                   // CFG: source 0 = TCXO, divider bypass
  MMW (Cmd + 8, 0);
  MMW (Cmd + 0xC, 0);
  MMW (Cmd + 0x10, 0);
  MMW (Cmd, MMR (Cmd) | 1U);                                          // UPDATE
  Ok = TouchWaitClear (Cmd, 1U, 20000);
  MMW (Cmd, MMR (Cmd) | 2U);                                          // ROOT_EN
  MMW (GCC_QUP_EN, MMR (GCC_QUP_EN) | (1U << 26));                    // SE4 clock gate
  Ok = Ok && TouchWaitClear (GCC_B + 0x183BC, 0x80000000U, 20000);
  PL ("TOUCH: gcc after : qup_en=0x%08x s4 halt=0x%08x rcg cmd=0x%08x cfg=0x%08x ok=%u%a", MMR (GCC_QUP_EN), MMR (GCC_B + 0x183BC), MMR (Cmd), MMR (Cmd + 4), Ok, "\n");
  PL ("TOUCH: ahb halts: m=0x%08x s=0x%08x%a", MMR (GCC_B + 0x2313C), MMR (GCC_B + 0x23140), "\n");
  return Ok;
}

// Apps SMMU (arm-smmu v2, 0x15000000): the QUP wrapper 1 DMA master is stream id 0xa3 (DT iommus = <&apps_smmu 0xa3 0x0>).  Dump the global stream mapping so we can see what UEFI left for it.
#define SMMU_B  0x15000000ULL

STATIC VOID
SmmuDump (IN UINT32 Sid)
{
  UINT32  Id0, Id1, NumSmrg, I, Hits = 0;

  PcEnsureMmio (SMMU_B, 0x100000, "SMMU");
  Id0 = MMR (SMMU_B + 0x20);
  Id1 = MMR (SMMU_B + 0x24);
  NumSmrg = Id0 & 0xFF;
  PL ("SMMU: idr0=0x%08x idr1=0x%08x nscr0=0x%08x sgfsr=0x%08x numsmrg=%u%a", Id0, Id1, MMR (SMMU_B + 0x0), MMR (SMMU_B + 0x48), NumSmrg, "\n");
  for (I = 0; I < NumSmrg && I < 256; I++) {
    UINT32  Smr = MMR (SMMU_B + 0x800 + 4ULL * I), S2cr = MMR (SMMU_B + 0xC00 + 4ULL * I);
    UINT32  Id = Smr & 0x7FFF, Mask = (Smr >> 16) & 0x7FFF;
    if ((Smr & 0x80000000U) != 0 && ((Sid ^ Id) & ~Mask & 0x7FFF) == 0) {
      PL ("SMMU: smr[%u]=0x%08x s2cr[%u]=0x%08x  <-- matches sid 0x%x%a", I, Smr, I, S2cr, Sid, "\n");
      Hits++;
    }
  }
  PL ("SMMU: %u matching entries for sid 0x%x; s2cr[0]=0x%08x s2cr[last]=0x%08x%a", Hits, Sid, MMR (SMMU_B + 0xC00), MMR (SMMU_B + 0xC00 + 4ULL * (NumSmrg - 1)), "\n");
}

// UEFI leaves sCR0.USFCFG = 1 (unmatched stream = fault) and nothing for the QUP wrapper-1 DMA master (stream 0xa3), so its first DMA access is fatal; and this SMMU turns S2CR TYPE=bypass into fault,
// so give the stream a stage-1 translation context with an identity map of the low 4 GB (four 1 GB block descriptors, AArch32 long-descriptor format, 32-bit VA).
// arm-smmu v2: global SMR[n] @0x800+4n, S2CR[n] @0xC00+4n (CBNDX 7:0, TYPE 17:16), CBAR[n] @0x1000+4n, CBA2R[n] @0x1800+4n; context bank n at cb_base + n*0x1000 (cb_base = base + 0x80000 here):
// SCTLR 0x0, TTBCR2 0x10, TTBR0 0x20 (64 bit), TTBCR 0x30, MAIR0 0x38, TLBIALL 0x618, TLBSYNC 0x7F0, TLBSTATUS 0x7F4.
#define SMMU_CB_B  (SMMU_B + 0x80000ULL)

// The stage-1 table must outlive MuChain: it is read by the SMMU while Windows runs, so it lives in EfiReservedMemoryType pages (a static array sits in boot-services memory that Windows reuses).
STATIC UINT64  *mSmmuPgd = NULL;

// The SMMU keeps its stream-match entries and context banks across the warm resets between our test boots, so every boot used to ADD another entry for the same stream (multiple matches / a stale context bank with
// an older table) - forget the entries of this stream before mapping it again.
STATIC VOID
SmmuForgetSid (IN UINT32 Sid)
{
  UINT32  Num = MMR (SMMU_B + 0x20) & 0xFF, I, Smr, S2cr, Cb, Freed = 0;

  for (I = 0; I < Num; I++) {
    Smr  = MMR (SMMU_B + 0x800 + 4ULL * I);
    S2cr = MMR (SMMU_B + 0xC00 + 4ULL * I);
    if ((Smr & 0x80000000U) != 0 && (Smr & 0x7FFF) == (Sid & 0x7FFF) && ((Smr >> 16) & 0x7FFF) == 0) {
      if (((S2cr >> 16) & 3) == 0) {
        Cb = S2cr & 0xFF;
        MMW (SMMU_CB_B + 0x1000ULL * Cb + 0x0, 0);                              // SCTLR: context bank off
        MMW (SMMU_CB_B + 0x1000ULL * Cb + 0x58, 0xFFFFFFFFU);                   // FSR: clear
        MMW (SMMU_B + 0x1000 + 4ULL * Cb, 0);                                   // CBAR: free
        MMW (SMMU_B + 0x1800 + 4ULL * Cb, 0);                                   // CBA2R: AArch32 format
      }
      MMW (SMMU_B + 0x800 + 4ULL * I, 0);                                       // SMR: invalid
      MMW (SMMU_B + 0xC00 + 4ULL * I, 0x00020000U);                             // S2CR: TYPE 2 (fault), the state the free-entry search looks for
      Freed++;
    }
  }
  PL ("SMMU: forgot %u stale stream-match entries of sid 0x%x\n", Freed, Sid);
}

STATIC BOOLEAN
SmmuBypassSid (IN UINT32 Sid)
{
  UINT32  Num = MMR (SMMU_B + 0x20) & 0xFF, NumCb = MMR (SMMU_B + 0x24) & 0xFF, I, N = 0xFFFFFFFF, Cb = 0xFFFFFFFF, R, T;
  UINT64  CbB;

  // a free stream-match entry
  for (I = Num; I > 0; I--) {
    UINT32  Smr = MMR (SMMU_B + 0x800 + 4ULL * (I - 1)), S2cr = MMR (SMMU_B + 0xC00 + 4ULL * (I - 1));
    if ((Smr & 0x80000000U) == 0 && ((S2cr >> 16) & 3) == 2) {
      N = I - 1;
      break;
    }
  }
  // a free context bank (stage-1 off, CBAR type 0)
  for (I = NumCb; I > 0; I--) {
    if ((MMR (SMMU_CB_B + 0x1000ULL * (I - 1)) & 1U) == 0 && (MMR (SMMU_B + 0x1000 + 4ULL * (I - 1)) & 0x30000U) == 0) {
      Cb = I - 1;
      break;
    }
  }
  PL ("SMMU: using smr/s2cr entry %u and context bank %u (of %u)%a", N, Cb, NumCb, "\n");
  if (N == 0xFFFFFFFF || Cb == 0xFFFFFFFF) {
    return FALSE;
  }
  if (mSmmuPgd == NULL) {
    EFI_PHYSICAL_ADDRESS  Pg = 0;
    if (EFI_ERROR (gBS->AllocatePages (AllocateAnyPages, EfiReservedMemoryType, 1, &Pg))) {
      PL ("SMMU: cannot allocate the reserved page for the stage-1 table%a", "\n");
      return FALSE;
    }
    SetMem ((VOID *)(UINTN)Pg, 4096, 0);
    mSmmuPgd = (UINT64 *)(UINTN)Pg;
    PL ("SMMU: stage-1 table at 0x%lx (reserved memory)%a", (UINT64)Pg, "\n");
  }
  CbB = SMMU_CB_B + 0x1000ULL * Cb;
  // identity map: 1 GB blocks, normal write-back, inner shareable, RW, access flag set
  for (I = 0; I < 4; I++) {
    // blocks 0 and 1 (0-2 GB) are peripherals (the ITS doorbell GITS_TRANSLATER 0x17150040 is in block 0): Device-nGnRnE (MAIR attr 1); blocks 2 and 3 are DRAM: normal write-back (attr 0)
    mSmmuPgd[I] = ((UINT64)I << 30) | (1ULL << 10) | (3ULL << 8) | (1ULL << 6) | ((I < 2) ? (1ULL << 2) : 0) | 1ULL;
  }
  GeniCacheOp (mSmmuPgd, 4 * sizeof (UINT64));
  MMW (SMMU_B + 0x1800 + 4ULL * Cb, 0);                                       // CBA2R: AArch32 format (VA64 = 0)
  MMW (SMMU_B + 0x1000 + 4ULL * Cb, 0x00010000);                              // CBAR: stage 1 translation, stage 2 bypass
  MMW (CbB + 0x30, 0x80003500U | (1U << 23));                                 // TTBCR: EAE, T0SZ 0, IRGN0=ORGN0=1 (WB), SH0=3, EPD1 (no TTBR1)
  MMW (CbB + 0x10, 0);                                                        // TTBCR2
  MMW (CbB + 0x20, (UINT32)(UINTN)mSmmuPgd);                                  // TTBR0 low
  MMW (CbB + 0x24, (UINT32)(((UINT64)(UINTN)mSmmuPgd) >> 32));                // TTBR0 high (ASID 0)
  MMW (CbB + 0x38, 0x000000FF);                                              // MAIR0: attr 0 = normal WB, attr 1 = Device-nGnRnE
  MMW (CbB + 0x618, 0);                                                       // TLBIALL
  MMW (CbB + 0x7F0, 0);                                                       // TLBSYNC
  for (T = 0; T < 1000 && (MMR (CbB + 0x7F4) & 1U) != 0; T++) {
    gBS->Stall (10);
  }
  MMW (CbB + 0x58, 0xFFFFFFFFU);                                              // FSR: clear a fault left over from an earlier boot (the context banks keep their state across warm resets)
  MMW (CbB + 0x0, 0x27);                                                      // SCTLR: M | TRE | AFE | CFRE (no CFIE: an unhandled context-fault interrupt hangs Windows; the fault is only latched in FSR/FAR)
  MMW (SMMU_B + 0xC00 + 4ULL * N, Cb);                                        // S2CR: TYPE 0 (translate), CBNDX = Cb
  MMW (SMMU_B + 0x800 + 4ULL * N, 0x80000000U | (Sid & 0x7FFF));              // SMR: valid, id = Sid
  R = MMR (SMMU_B + 0xC00 + 4ULL * N);
  PL ("SMMU: readback s2cr=0x%08x smr=0x%08x cbar=0x%08x cba2r=0x%08x sctlr=0x%08x ttbcr=0x%08x ttbr0=0x%08x_%08x mair0=0x%08x%a", R, MMR (SMMU_B + 0x800 + 4ULL * N), MMR (SMMU_B + 0x1000 + 4ULL * Cb),
      MMR (SMMU_B + 0x1800 + 4ULL * Cb), MMR (CbB), MMR (CbB + 0x30), MMR (CbB + 0x24), MMR (CbB + 0x20), MMR (CbB + 0x38), "\n");
  return ((R >> 16) & 3) == 0 && (R & 0xFF) == Cb && (MMR (CbB) & 1U) != 0;
}

STATIC VOID
TouchLoop (IN UINT32 Seconds)
{
  UINT8      F[26], Z = 0, V[28], Aa[8];
  UINT32     T, Ev = 0, Err = 0, I, N;
  EFI_EVENT  PetEv = NULL;

  SetMem (Aa, sizeof (Aa), 0xAA);
  if (GoodixWrite (0x00010000, Aa, 8) && GoodixRead (0x00010000, V, 8)) {         // dev_confirm() of the mainline driver
    PL ("TOUCH: confirm readback %02x %02x %02x %02x %02x %02x %02x %02x%a", V[0], V[1], V[2], V[3], V[4], V[5], V[6], V[7], "\n");
  }
  gBS->Stall (200000);
  if (GoodixRead (0x00010014, V, 28)) {
    PL ("TOUCH: version block:", 0);
    for (I = 0; I < 28; I++) {
      PL (" %02x", V[I]);
    }
    PL ("\n");
  }
  if (!EFI_ERROR (gBS->CreateEvent (EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, WdtPetCb, NULL, &PetEv))) {
    gBS->SetTimer (PetEv, TimerPeriodic, 10000000);
  }
  PL ("TOUCH: >>> touch the screen now (%u s)%a", Seconds, "\n");
  for (T = 0; T < Seconds * 200; T++) {
    if (!GoodixRead (0x00010308, F, 26)) {
      Err++;
      continue;
    }
    if (F[0] != 0) {
      Ev++;
      N = F[2] & 0xF;
      if (Ev <= 300) {
        PL ("TOUCH: ev#%u t=%u status=%02x cnt=%u  p0: st=%02x x=%u y=%u w=%u  p1: st=%02x x=%u y=%u w=%u%a", Ev, T / 200, F[0], N,
            F[8], F[10] | (F[11] << 8), F[12] | (F[13] << 8), F[14] | (F[15] << 8), F[16], F[18] | (F[19] << 8), F[20] | (F[21] << 8), F[22] | (F[23] << 8), "\n");
      }
      GoodixWrite (0x00010308, &Z, 1);                                              // ack
    }
    gBS->Stall (5000);
  }
  if (PetEv != NULL) {
    gBS->SetTimer (PetEv, TimerCancel, 0);
  }
  PL ("TOUCH: loop done: %u frames with status!=0, %u read errors%a", Ev, Err, "\n");
}

STATIC VOID
TouchProbe (IN BOOLEAN SetupOnly)
{
  UINT8   B[8];
  UINT32  I;

  PcEnsureMmio (SE4_B, 0x4000, "SE4");
  PcEnsureMmio (0x00AC0000ULL, 0x4000, "QUP1");
  TouchSpiPins ();
  TouchPowerUp ();
  if (!TouchClocks ()) {
    PL ("TOUCH: clocks did not come up, stopping%a", "\n");
    return;
  }
  SmmuDump (0xA3);
  if (!SmmuBypassSid (0xA3)) {
    PL ("TOUCH: could not open the SMMU for the QUP DMA, stopping\n");
    return;
  }
  SmmuDump (0xA3);
  GeniSeDump ();
  if (!GeniSpiInit (1)) {
    PL ("TOUCH: GENI SE4 looks dead%a", "\n");
    return;
  }
  if (SetupOnly) {
    PL ("TOUCH: setup left powered for Windows (SMMU stream 0xA3 mapped, SE4 initialised)%a", "\n");
    return;
  }
  for (I = 0; I < 3; I++) {
    SetMem (B, sizeof (B), 0xEE);
    if (GoodixRead (0x00002000, B, 4)) {
      PL ("TOUCH: read 0x2000 -> %02x %02x %02x %02x (Android: e0 35 02 00)%a", B[0], B[1], B[2], B[3], "\n");
    } else {
      PL ("TOUCH: read 0x2000 failed%a", "\n");
    }
    gBS->Stall (100000);
  }
  if (GoodixRead (0x00010014, B, 8)) {
    PL ("TOUCH: read 0x10014 -> %02x %02x %02x %02x %02x %02x %02x %02x%a", B[0], B[1], B[2], B[3], B[4], B[5], B[6], B[7], "\n");
  }
  TouchLoop (45);
}

STATIC VOID
TouchPowerDown (VOID)
{
  UINT32  A = CmdDbAddr ("ldob14");

  PcGpio (161, 0x200, 0);
  PcGpio (28, 0x200, 0);
  if (A != 0) {
    RpmhWrite (A + 0x4, 0);                     // AVDD off again
  }
  MMW (GCC_QUP_EN, MMR (GCC_QUP_EN) & ~(1U << 26));
  PL ("TOUCH: powered down%a", "\n");
}

// ===== PANEL.TXT (+ PANEL60/90/120.TXT): switch the DSI command-mode panel's refresh rate with the panel's own timing-switch DCS sequences (from its device tree), sent through DSI0's command DMA.
// The bootloader (ABL) leaves the panel at 60 Hz; the TE pin (TLMM gpio86 = mdp_vsync) shows the real scan rate, which is measured before and after.
// DSI host (dsi.xml of the msm driver): CTRL 0x00, STATUS0 0x04 (bit1 DMA busy), CMD_DMA_CTRL 0x38 (bit26 LOW_POWER), DMA_BASE 0x44, DMA_LEN 0x48, TRIG_CTRL 0x80, TRIG_DMA 0x8c, INTR_CTRL 0x10c (bit0 DMA_DONE status, bit1 mask).
// DMA packet layout (dsi_cmd_dma_add): byte0 WC lo, byte1 WC hi, byte2 data type (|vc<<6), byte3 flags (0x80 last, 0x40 long packet), payload from byte4, padded with 0xFF to a multiple of 4.
#define DSI0_B       0x0AE94000ULL
#define DSI_REG(o)   (DSI0_B + 4ULL + (o))      // 6G host (msm dsi_cfg DSI_6G_REG_SHIFT): offset 0 is HW_VERSION (reads 0x20080000 = 2.8.0), dsi.xml offsets are +4 on the real block
#define TE_GPIO_IN   (0x0F100000ULL + 0x1000ULL * 86 + 4)
#define PANEL_FB     0xE3940000ULL
#define PANEL_BUF    (PANEL_FB + 1116ULL * 2480ULL * 4ULL - 8192ULL)    // last 8 KB of the visible framebuffer: mapped for the MDSS SMMU context; saved and restored around the transfer

STATIC CONST UINT8  mPanelSeq60[] = {
  0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfe, 0x40, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02,
  0xbd, 0x00, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfe, 0x5a, 0x39, 0x00, 0x00, 0x40, 0x00,
  0x00, 0x0d, 0x49, 0x5e, 0xff, 0xf0, 0xff, 0xff, 0xff, 0xf0, 0xff, 0xff, 0x00, 0xfd, 0xfd, 0x39,
  0x00, 0x00, 0x40, 0x00, 0x00, 0x03, 0x58, 0x16, 0xfa, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x05,
  0x5e, 0x0f, 0x0f, 0x0f, 0x05, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x04, 0x66, 0x00, 0x00, 0x00,
  0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x03, 0x6e, 0x00, 0x00, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
  0x03, 0x7e, 0x00, 0x00, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x04, 0x92, 0x4e, 0x22, 0x1f, 0x39,
  0x00, 0x00, 0x40, 0x00, 0x00, 0x05, 0x99, 0x2d, 0x24, 0x0c, 0x00, 0x39, 0x00, 0x00, 0x40, 0x00,
  0x00, 0x04, 0x9e, 0x20, 0x20, 0x20, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x03, 0xa2, 0x10, 0x03,
  0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xa7, 0x10, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x03,
  0xa9, 0x10, 0x0d, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xac, 0x00, 0x39, 0x00, 0x00, 0x40,
  0x00, 0x00, 0x06, 0xb0, 0x08, 0x08, 0x05, 0x05, 0x00, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x06,
  0xb8, 0x09, 0x09, 0x05, 0x00, 0x00, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x05, 0xc0, 0x08, 0x08,
  0x03, 0x00, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x04, 0xc8, 0x06, 0x06, 0x02, 0x39, 0x00, 0x00,
  0x40, 0x00, 0x00, 0x02, 0xea, 0x16, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfe, 0x5b, 0x39,
  0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x2b, 0x4b, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x2d,
  0x24, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x2f, 0x1f, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
  0x0d, 0x30, 0x1f, 0x3f, 0x3f, 0x38, 0x32, 0x24, 0x0c, 0x00, 0x00, 0x25, 0x25, 0x1d, 0x39, 0x00,
  0x00, 0x40, 0x00, 0x00, 0x02, 0x3d, 0x11, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x3f, 0x07,
  0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x0a, 0x40, 0x04, 0x00, 0x00, 0x1a, 0x1a, 0x0e, 0x08, 0x03,
  0x00, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x05, 0x4b, 0x08, 0x08, 0x08, 0x08, 0x39, 0x00, 0x00,
  0x40, 0x00, 0x00, 0x02, 0x50, 0x00, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x05, 0x53, 0x09, 0x09,
  0x05, 0x02, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x58, 0x00, 0x39, 0x00, 0x00, 0x40, 0x00,
  0x00, 0x06, 0x5c, 0x08, 0x08, 0x04, 0x01, 0x00, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x05, 0x64,
  0x07, 0x07, 0x03, 0x01, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xfe, 0x00,
};

STATIC CONST UINT8  mPanelSeq90[] = {
  0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfe, 0x40, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02,
  0xbd, 0x06, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfe, 0x5a, 0x39, 0x00, 0x00, 0x40, 0x00,
  0x00, 0x0b, 0x49, 0x0f, 0x08, 0x04, 0x00, 0x06, 0x06, 0x06, 0x06, 0x06, 0x04, 0x39, 0x00, 0x00,
  0x40, 0x00, 0x00, 0x03, 0x55, 0x03, 0x03, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x0a, 0x58, 0x03,
  0x03, 0x0f, 0x0f, 0x0f, 0x0a, 0x10, 0x10, 0x10, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x03, 0x6e,
  0x0a, 0x0a, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x03, 0x76, 0x0a, 0x0a, 0x39, 0x00, 0x00, 0x40,
  0x00, 0x00, 0x03, 0x7e, 0x0a, 0x0a, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x04, 0x92, 0x7f, 0x3a,
  0x25, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x05, 0x99, 0x2d, 0x30, 0x0f, 0x03, 0x39, 0x00, 0x00,
  0x40, 0x00, 0x00, 0x04, 0x9e, 0x20, 0x20, 0x20, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x03, 0xa2,
  0x25, 0x0e, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xa7, 0x10, 0x39, 0x00, 0x00, 0x40, 0x00,
  0x00, 0x03, 0xa9, 0x10, 0x15, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xac, 0x00, 0x39, 0x00,
  0x00, 0x40, 0x00, 0x00, 0x06, 0xb0, 0x08, 0x08, 0x0a, 0x05, 0x03, 0x39, 0x00, 0x00, 0x40, 0x00,
  0x00, 0x06, 0xb8, 0x0f, 0x0f, 0x0d, 0x03, 0x00, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x05, 0xc0,
  0x0a, 0x0a, 0x06, 0x01, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x04, 0xc8, 0x09, 0x09, 0x05, 0x39,
  0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xea, 0x16, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfe,
  0x5b, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x2b, 0x6a, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
  0x02, 0x2d, 0x3f, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x0e, 0x2f, 0x2f, 0x7a, 0x3f, 0x3f, 0x38,
  0x2f, 0x30, 0x15, 0x0a, 0x0a, 0x25, 0x25, 0x1b, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x3d,
  0x1f, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x0b, 0x3f, 0x0f, 0x07, 0x02, 0x01, 0x1a, 0x1a, 0x16,
  0x0a, 0x04, 0x01, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x05, 0x4b, 0x08, 0x08, 0x09, 0x06, 0x39,
  0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x50, 0x00, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x05, 0x53,
  0x0c, 0x0c, 0x0a, 0x05, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x58, 0x01, 0x39, 0x00, 0x00,
  0x40, 0x00, 0x00, 0x06, 0x5c, 0x08, 0x08, 0x06, 0x02, 0x01, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
  0x05, 0x64, 0x07, 0x07, 0x04, 0x02, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xfe, 0x00,
};

STATIC CONST UINT8  mPanelSeq120[] = {
  0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfe, 0x40, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02,
  0xbd, 0x05, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfe, 0x5a, 0x39, 0x00, 0x00, 0x40, 0x00,
  0x00, 0x0b, 0x49, 0x0f, 0x08, 0x04, 0x00, 0x06, 0x06, 0x06, 0x06, 0x06, 0x04, 0x39, 0x00, 0x00,
  0x40, 0x00, 0x00, 0x03, 0x55, 0x10, 0x10, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x03, 0x58, 0x05,
  0x03, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x05, 0x5e, 0x0f, 0x0f, 0x0f, 0x0a, 0x39, 0x00, 0x00,
  0x40, 0x00, 0x00, 0x04, 0x66, 0x10, 0x10, 0x10, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x03, 0x6e,
  0x05, 0x05, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x03, 0x76, 0x05, 0x05, 0x39, 0x00, 0x00, 0x40,
  0x00, 0x00, 0x03, 0x7e, 0x05, 0x05, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x04, 0x92, 0x72, 0x45,
  0x25, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x05, 0x99, 0x7f, 0x40, 0x0f, 0x03, 0x39, 0x00, 0x00,
  0x40, 0x00, 0x00, 0x04, 0x9e, 0x30, 0x10, 0x3d, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x03, 0xa2,
  0x1d, 0x09, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xa7, 0x27, 0x39, 0x00, 0x00, 0x40, 0x00,
  0x00, 0x03, 0xa9, 0x27, 0x1a, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xac, 0x04, 0x39, 0x00,
  0x00, 0x40, 0x00, 0x00, 0x06, 0xb0, 0x20, 0x10, 0x0a, 0x0d, 0x03, 0x39, 0x00, 0x00, 0x40, 0x00,
  0x00, 0x06, 0xb8, 0x12, 0x12, 0x0d, 0x03, 0x02, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x05, 0xc0,
  0x0e, 0x0e, 0x09, 0x03, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x04, 0xc8, 0x0b, 0x0b, 0x07, 0x39,
  0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xea, 0x1f, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0xfe,
  0x5b, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x2b, 0x7a, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00,
  0x02, 0x2d, 0x45, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x2f, 0x32, 0x39, 0x00, 0x00, 0x40,
  0x00, 0x00, 0x0d, 0x31, 0x60, 0x1f, 0x60, 0x60, 0x60, 0x37, 0x18, 0x0f, 0x0a, 0x30, 0x30, 0x2b,
  0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x3d, 0x1f, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x0b,
  0x3f, 0x0f, 0x07, 0x02, 0x01, 0x1b, 0x1b, 0x1b, 0x0e, 0x06, 0x02, 0x39, 0x00, 0x00, 0x40, 0x00,
  0x00, 0x05, 0x4b, 0x13, 0x13, 0x0d, 0x09, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x02, 0x50, 0x01,
  0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x05, 0x53, 0x12, 0x12, 0x0b, 0x05, 0x39, 0x00, 0x00, 0x40,
  0x00, 0x00, 0x02, 0x58, 0x03, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x06, 0x5c, 0x0b, 0x0d, 0x08,
  0x04, 0x02, 0x39, 0x00, 0x00, 0x40, 0x00, 0x00, 0x06, 0x5c, 0x0b, 0x00, 0x08, 0x04, 0x02, 0x39,
  0x00, 0x00, 0x40, 0x00, 0x00, 0x05, 0x64, 0x09, 0x09, 0x06, 0x02, 0x39, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x02, 0xfe, 0x00,
};


STATIC UINT32
PanelTeHz10 (IN UINT32 Ms)
{
  UINT64  T0 = PcNowUs (), T;
  UINT32  Prev = MMR (TE_GPIO_IN) & 1, Cur, N = 0;

  do {
    Cur = MMR (TE_GPIO_IN) & 1;
    if (Prev && !Cur) {
      N++;
    }
    Prev = Cur;
    T = PcNowUs ();
  } while (T - T0 < (UINT64)Ms * 1000);
  return (UINT32)((UINT64)N * 10000000ULL / (T - T0));        // falling edges per second x 10
}

STATIC VOID
PanelDsiDump (IN CONST CHAR8 *Tag)
{
  PL ("PANEL %a: HWVER=%08x CTRL=%08x STATUS0=%08x FIFO=%08x CMD_DMA_CTRL=%08x DMA_BASE=%08x DMA_LEN=%08x TRIG_CTRL=%08x TRIG_DMA=%08x INTR=%08x CLK_CTRL=%08x LANE_CTRL=%08x%a", Tag, MMR (DSI0_B),
      MMR (DSI_REG (0x00)), MMR (DSI_REG (0x04)), MMR (DSI_REG (0x08)), MMR (DSI_REG (0x38)), MMR (DSI_REG (0x44)), MMR (DSI_REG (0x48)), MMR (DSI_REG (0x80)),
      MMR (DSI_REG (0x8C)), MMR (DSI_REG (0x10C)), MMR (DSI_REG (0x118)), MMR (DSI_REG (0xA8)), "\n");
}

STATIC BOOLEAN
PanelDsiSend (IN CONST UINT8 *Payload, IN UINT32 N, IN UINT8 Dt)
{
  UINT8   *B = (UINT8 *)(UINTN)PANEL_BUF;
  UINT32  Len = (4 + N + 3) & ~3U, I, T, Done = 0;

  B[0] = (UINT8)(N & 0xFF);
  B[1] = (UINT8)(N >> 8);
  B[2] = Dt;
  B[3] = 0x80 | 0x40;
  for (I = 0; I < N; I++) {
    B[4 + I] = Payload[I];
  }
  for (I = 4 + N; I < Len; I++) {
    B[I] = 0xFF;
  }
  GeniCacheOp (B, Len);
  MMW (DSI_REG (0x10C), MMR (DSI_REG (0x10C)) | 1U);              // ack a stale DMA_DONE
  MMW (DSI_REG (0x44), (UINT32)PANEL_BUF);
  MMW (DSI_REG (0x48), Len);
  MMW (DSI_REG (0x8C), 1);
  for (T = 0; T < 20000; T++) {                                 // ~200 ms
    if ((MMR (DSI_REG (0x10C)) & 1U) != 0) {
      Done = 1;
      break;
    }
    gBS->Stall (10);
  }
  if (!Done) {
    PL ("PANEL: DMA_DONE timeout (status0=%08x intr=%08x)%a", MMR (DSI_REG (0x04)), MMR (DSI_REG (0x10C)), "\n");
    return FALSE;
  }
  MMW (DSI_REG (0x10C), MMR (DSI_REG (0x10C)) | 1U);
  return TRUE;
}

STATIC UINT32
PanelRunSeq (IN CONST UINT8 *Seq, IN UINT32 SeqLen)
{
  UINT32  P = 0, Cnt = 0, N;

  while (P + 7 <= SeqLen) {
    N = ((UINT32)Seq[P + 5] << 8) | Seq[P + 6];
    if (P + 7 + N > SeqLen) {
      break;
    }
    if (!PanelDsiSend (&Seq[P + 7], N, Seq[P])) {
      PL ("PANEL: packet %u failed%a", Cnt, "\n");
      return Cnt;
    }
    if (Seq[P + 4] != 0) {
      gBS->Stall ((UINTN)Seq[P + 4] * 1000);
    }
    P += 7 + N;
    Cnt++;
  }
  return Cnt;
}

STATIC VOID
PanelMain (VOID)
{
  CONST UINT8  *Seq = NULL;
  UINT32       SeqLen = 0, Hz, I, Cnt, Save[128], Want = 0;
  UINT32       *Buf = (UINT32 *)(UINTN)PANEL_BUF;
  EFI_EVENT    PetEv = NULL;

  if (SelfFileExists (L"\\PANEL60.TXT")) {
    Seq = mPanelSeq60;  SeqLen = sizeof (mPanelSeq60);  Want = 60;
  } else if (SelfFileExists (L"\\PANEL90.TXT")) {
    Seq = mPanelSeq90;  SeqLen = sizeof (mPanelSeq90);  Want = 90;
  } else if (SelfFileExists (L"\\PANEL120.TXT")) {
    Seq = mPanelSeq120; SeqLen = sizeof (mPanelSeq120); Want = 120;
  }
  PcEnsureMmio (DSI0_B, 0x1000, "DSI0");
  if (!EFI_ERROR (gBS->CreateEvent (EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, WdtPetCb, NULL, &PetEv))) {
    gBS->SetTimer (PetEv, TimerPeriodic, 10000000);
  }
  Hz = PanelTeHz10 (500);
  PL ("PANEL: TE (gpio86) before = %u.%u Hz%a", Hz / 10, Hz % 10, "\n");
  PanelDsiDump ("before");
  SmmuDump (0x1C00);
  SmmuDump (0x1C01);
  if (Seq != NULL) {
    for (I = 0; I < 128; I++) {
      Save[I] = Buf[I];
    }
    MMW (DSI_REG (0x38), MMR (DSI_REG (0x38)) | (1U << 26));              // low-power DCS
    MMW (DSI_REG (0x10C), MMR (DSI_REG (0x10C)) | 2U);                    // unmask DMA_DONE
    MMW (DSI_REG (0x80), (MMR (DSI_REG (0x80)) & ~((7U << 0) | (1U << 12))) | 4U);   // DMA trigger = SW (the MDP stream trigger is left alone)
    PanelDsiDump ("prepared");
    Cnt = PanelRunSeq (Seq, SeqLen);
    PL ("PANEL: sent %u packets of the %u Hz sequence%a", Cnt, Want, "\n");
    for (I = 0; I < 128; I++) {
      Buf[I] = Save[I];
    }
    GeniCacheOp (Buf, 512);
    gBS->Stall (100000);
    PanelDsiDump ("after");
    for (I = 0; I < 3; I++) {
      Hz = PanelTeHz10 (500);
      PL ("PANEL: TE (gpio86) after = %u.%u Hz%a", Hz / 10, Hz % 10, "\n");
    }
  }
  if (PetEv != NULL) {
    gBS->SetTimer (PetEv, TimerCancel, 0);
  }
}

// ===== USBREPLAY.TXT + NOBOOT: replay of Android's USB device-mode bring-up (final cycle of the boot-time MMIO trace, winboot/usbtrace2) from UEFI, without any Windows USB stack in between:
//   eUSB2 HS PHY init, QMP SS PHY init, dwc3 core soft reset / init / prtcap=device / event buffers, dwc3_msm QSCRATCH + glue writes, DCFG/DEVTEN, RUN.  Then the DWC3 state and the PC-side result are watched.
//   Success markers: GEVNTCOUNT0 > 0 / DSTS changes / a new (failing) USB device on the PC.
// generated by refs/usbreplay_gen.py from the Android boot-time MMIO trace (winboot/usbtrace2): eUSB2 HS PHY init (base 0x88E3000) and QMP SS PHY init (base 0x88E8000), in Android order
STATIC CONST UINT32  mUrEusb2[][2] = {
  { 0x0094, 0x00000002 },
  { 0x0050, 0x00000002 },
  { 0x0054, 0x09090909 },
  { 0x0130, 0x00000004 },
  { 0x0098, 0x00000000 },
  { 0x00b8, 0x00000001 },
  { 0x0054, 0x09090949 },
  { 0x005c, 0xc8c8c8c8 },
  { 0x0060, 0x00000000 },
  { 0x0060, 0x00000000 },
  { 0x0058, 0x02020202 },
  { 0x0068, 0x21212121 },
  { 0x0068, 0x21212121 },
  { 0x006c, 0x50505050 },
  { 0x0070, 0x00000000 },
  { 0x006c, 0x50505050 },
  { 0x0064, 0x07070717 },
  { 0x007c, 0xc8c8c8c8 },
  { 0x007c, 0xc8c8c8c8 },
  { 0x007c, 0xc8c8c8c8 },
  { 0x0078, 0x18181818 },
  { 0x0078, 0x18181818 },
  { 0x0064, 0x1717171f },
  { 0x003c, 0x01010101 },
  { 0x0054, 0x4949494b },
  { 0x0054, 0x4b4b4b4b },
  { 0x0050, 0x02020200 },
  { 0x0064, 0x1f1f1f17 },
};

STATIC CONST UINT32  mUrQmp[][2] = {
  { 0x0008, 0x00000001 },
  { 0x1c40, 0x00000001 },
  { 0x0004, 0x00000001 },
  { 0x0004, 0x00000000 },
  { 0x001c, 0x0000000f },
  { 0x0000, 0x00000003 },
  { 0x001c, 0x00000000 },
  { 0x0008, 0x00000001 },
  { 0x1c40, 0x00000001 },
  { 0x1000, 0x000000c0 },
  { 0x1004, 0x00000001 },
  { 0x1010, 0x00000002 },
  { 0x1014, 0x00000016 },
  { 0x1018, 0x00000036 },
  { 0x101c, 0x00000004 },
  { 0x1020, 0x00000016 },
  { 0x1024, 0x00000041 },
  { 0x1028, 0x00000041 },
  { 0x102c, 0x00000000 },
  { 0x1030, 0x00000055 },
  { 0x1034, 0x00000075 },
  { 0x1038, 0x00000001 },
  { 0x103c, 0x00000001 },
  { 0x1048, 0x00000025 },
  { 0x104c, 0x00000002 },
  { 0x1050, 0x0000005c },
  { 0x1054, 0x0000000f },
  { 0x1058, 0x0000005c },
  { 0x105c, 0x0000000f },
  { 0x1060, 0x000000c0 },
  { 0x1064, 0x00000001 },
  { 0x1070, 0x00000002 },
  { 0x1074, 0x00000016 },
  { 0x1078, 0x00000036 },
  { 0x1080, 0x00000008 },
  { 0x1084, 0x0000001a },
  { 0x1088, 0x00000041 },
  { 0x108c, 0x00000000 },
  { 0x1090, 0x00000055 },
  { 0x1094, 0x00000075 },
  { 0x1098, 0x00000001 },
  { 0x10a8, 0x00000025 },
  { 0x10ac, 0x00000002 },
  { 0x10bc, 0x0000000a },
  { 0x10c0, 0x00000001 },
  { 0x10cc, 0x00000062 },
  { 0x10d0, 0x00000002 },
  { 0x10e8, 0x0000000c },
  { 0x1110, 0x0000001a },
  { 0x1124, 0x00000014 },
  { 0x1140, 0x00000004 },
  { 0x1170, 0x00000020 },
  { 0x1174, 0x00000016 },
  { 0x11a4, 0x000000b6 },
  { 0x11a8, 0x0000004b },
  { 0x11ac, 0x00000037 },
  { 0x11b4, 0x0000000c },
  { 0x1234, 0x00000000 },
  { 0x1238, 0x00000000 },
  { 0x123c, 0x0000001f },
  { 0x1240, 0x00000009 },
  { 0x1284, 0x000000f5 },
  { 0x128c, 0x0000003f },
  { 0x1290, 0x0000003f },
  { 0x1294, 0x0000005f },
  { 0x12a4, 0x00000012 },
  { 0x12e4, 0x00000021 },
  { 0x1408, 0x0000000a },
  { 0x1414, 0x00000006 },
  { 0x1430, 0x0000002f },
  { 0x1434, 0x0000007f },
  { 0x143c, 0x000000ff },
  { 0x1440, 0x0000000f },
  { 0x1444, 0x00000099 },
  { 0x144c, 0x00000008 },
  { 0x1450, 0x00000008 },
  { 0x1454, 0x00000000 },
  { 0x1458, 0x0000000a },
  { 0x1460, 0x000000a0 },
  { 0x14d4, 0x00000054 },
  { 0x14d8, 0x0000000f },
  { 0x14dc, 0x00000013 },
  { 0x14ec, 0x0000000f },
  { 0x14f0, 0x0000004a },
  { 0x14f4, 0x0000000a },
  { 0x14f8, 0x00000007 },
  { 0x14fc, 0x00000000 },
  { 0x1510, 0x00000047 },
  { 0x151c, 0x00000004 },
  { 0x1524, 0x0000000e },
  { 0x155c, 0x0000003f },
  { 0x1560, 0x000000bf },
  { 0x1564, 0x000000ff },
  { 0x1568, 0x000000df },
  { 0x156c, 0x000000ed },
  { 0x1570, 0x000000dc },
  { 0x1574, 0x0000005c },
  { 0x1578, 0x0000009f },
  { 0x157c, 0x0000001d },
  { 0x1580, 0x0000003d },
  { 0x15a0, 0x00000004 },
  { 0x15a4, 0x00000038 },
  { 0x15a8, 0x0000000c },
  { 0x15b0, 0x00000010 },
  { 0x15e4, 0x00000014 },
  { 0x15f8, 0x00000008 },
  { 0x1634, 0x00000000 },
  { 0x1638, 0x00000000 },
  { 0x163c, 0x0000001f },
  { 0x1640, 0x00000009 },
  { 0x1684, 0x000000f5 },
  { 0x168c, 0x0000003f },
  { 0x1690, 0x0000003f },
  { 0x1694, 0x0000005f },
  { 0x16a4, 0x00000012 },
  { 0x16e4, 0x00000005 },
  { 0x1808, 0x0000000a },
  { 0x1814, 0x00000006 },
  { 0x1830, 0x0000002f },
  { 0x1834, 0x0000007f },
  { 0x183c, 0x000000ff },
  { 0x1840, 0x0000000f },
  { 0x1844, 0x00000099 },
  { 0x184c, 0x00000008 },
  { 0x1850, 0x00000008 },
  { 0x1854, 0x00000000 },
  { 0x1858, 0x0000000a },
  { 0x1860, 0x000000a0 },
  { 0x18d4, 0x00000054 },
  { 0x18d8, 0x0000000f },
  { 0x18dc, 0x00000013 },
  { 0x18ec, 0x0000000f },
  { 0x18f0, 0x0000004a },
  { 0x18f4, 0x0000000a },
  { 0x18f8, 0x00000007 },
  { 0x18fc, 0x00000000 },
  { 0x1910, 0x00000047 },
  { 0x191c, 0x00000004 },
  { 0x1924, 0x0000000e },
  { 0x195c, 0x000000bf },
  { 0x1960, 0x000000bf },
  { 0x1964, 0x000000bf },
  { 0x1968, 0x000000df },
  { 0x196c, 0x000000fd },
  { 0x1970, 0x000000dc },
  { 0x1974, 0x0000005c },
  { 0x1978, 0x0000009f },
  { 0x197c, 0x0000001d },
  { 0x1980, 0x0000003d },
  { 0x19a0, 0x00000004 },
  { 0x19a4, 0x00000038 },
  { 0x19a8, 0x0000000c },
  { 0x19b0, 0x00000010 },
  { 0x19e4, 0x00000014 },
  { 0x19f8, 0x00000008 },
  { 0x1cc4, 0x000000c4 },
  { 0x1cc8, 0x00000089 },
  { 0x1ccc, 0x00000020 },
  { 0x1cd8, 0x00000013 },
  { 0x1cdc, 0x00000021 },
  { 0x1d88, 0x00000099 },
  { 0x1d90, 0x000000e7 },
  { 0x1d94, 0x00000003 },
  { 0x1db0, 0x0000000a },
  { 0x1dc0, 0x00000088 },
  { 0x1dc4, 0x00000013 },
  { 0x1dd0, 0x0000000c },
  { 0x1ddc, 0x0000004b },
  { 0x1dec, 0x00000010 },
  { 0x1f00, 0x00000068 },
  { 0x1f18, 0x000000f8 },
  { 0x1f3c, 0x00000007 },
  { 0x1f40, 0x00000040 },
  { 0x1f44, 0x00000000 },
  { 0x1c00, 0x00000000 },
  { 0x1c44, 0x00000003 },
};


STATIC VOID
UrDwc3Reset (IN UINT64 U)
{
  UINT32  I;

  MMW (U + 0xC704, 0x40F00000U);                      // DCTL.CSFTRST
  for (I = 0; I < 2000; I++) {
    if ((MMR (U + 0xC704) & 0x40000000U) == 0) {
      break;
    }
    gBS->Stall (100);
  }
  PL ("UR: soft reset done after %u x100us, DCTL=0x%08x%a", I, MMR (U + 0xC704), "\n");
}

STATIC VOID
UrEventBuffers (IN UINT64 U, IN UINT32 Ev0, IN UINT32 Ev1)
{
  MMW (U + 0xC400, Ev0);              // GEVNTADRLO(0)
  MMW (U + 0xC404, 0);
  MMW (U + 0xC408, 0x1000);           // GEVNTSIZ(0)
  MMW (U + 0xC40C, 0);                // GEVNTCOUNT(0)
  (VOID)Ev1;
}

STATIC VOID
UrNotifyRings (IN UINT64 U, IN UINT32 Ev1)
{
  UINT32  K;

  for (K = 0; K < 3; K++) {            // GSI event rings 1..3 (masked, size 0x1000): point them at a harmless page of ours
    MMW (U + 0xC410 + 0x10 * K, Ev1);
    MMW (U + 0xC414 + 0x10 * K, 0);
    MMW (U + 0xC418 + 0x10 * K, 0x80001000U);
    MMW (U + 0xC41C + 0x10 * K, 0);
  }
}

STATIC VOID
UsbReplay (VOID)
{
  CONST UINT64          U = 0x0A600000ULL, Q = 0x0A6F8800ULL, H = 0x088E3000ULL, S = 0x088E8000ULL;
  EFI_PHYSICAL_ADDRESS  Pg = 0xFFFFFFFFULL;
  UINT32                I, J, T, Ev0, Ev1, St, W0, W1, Cc;
  UINT32                *Ev;
  EFI_EVENT             PetEv = NULL;

  if ((MMR (GCC_B + 0x39004) & 0x80000000U) == 0) {
    PL ("UR: USB GDSC off, nothing to do%a", "\n");
    return;
  }
  PcEnsureMmio (U, 0x100000, "DWC3");
  PcEnsureMmio (H, 0x2000, "EUSB2");
  PcEnsureMmio (S, 0x3000, "QMP");
  PcEnsureMmio (0x0C278000ULL, 0x1000, "EUDDET");
  if (EFI_ERROR (gBS->AllocatePages (AllocateMaxAddress, EfiBootServicesData, 2, &Pg))) {
    PL ("UR: no event buffer memory%a", "\n");
    return;
  }
  SetMem ((VOID *)(UINTN)Pg, 8192, 0);
  Ev0 = (UINT32)Pg;
  Ev1 = (UINT32)Pg + 0x1000;
  Ev = (UINT32 *)(UINTN)Pg;
  GeniCacheOp (Ev, 8192);
  if (!EFI_ERROR (gBS->CreateEvent (EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, WdtPetCb, NULL, &PetEv))) {
    gBS->SetTimer (PetEv, TimerPeriodic, 10000000);
  }
  SmmuDump (0x40);
  Cc = (mMgD != NULL) ? RtrConnStatus (&W0, &W1) : 0xFFFFFFFFU;
  PL ("UR: UCSI connector status cci=0x%08x word0=0x%08x word1=0x%08x (before)%a", Cc, W0, W1, "\n");
  UsbGoldenDump ("ur-before");

  // --- the clock / reset steps Android does just before the PHY writes (boot-time trace, winboot/usbtrace3): GDSCs, TCSR USB clkrefs, PHY aux/pipe clocks, the eUSB2 PHY BCR pulse (GCC+0x12000), the USB3 / DP PHY BCR pulses (GCC+0x50000 / 0x50008)
  PcEnsureMmio (GCC_B, 0x80000, "GCC");
  PcEnsureMmio (0x01FF1000ULL, 0x1000, "TCSRCLKREF");
  PL ("UR: gdsc usb30=0x%08x usb3phy=0x%08x tcsr clkref +0x108=0x%08x +0x118=0x%08x bcr phy=0x%08x dp=0x%08x qusb2=0x%08x aux=0x%08x comaux=0x%08x pipe=0x%08x%a",
      MMR (GCC_B + 0x39004), MMR (GCC_B + 0x50018), MMR (0x01FF1108ULL), MMR (0x01FF1118ULL), MMR (GCC_B + 0x50000), MMR (GCC_B + 0x50008), MMR (GCC_B + 0x12000),
      MMR (GCC_B + 0x39060), MMR (GCC_B + 0x39064), MMR (GCC_B + 0x39068), "\n");
  MMW (U + 0xC200, 0x00102500U);                      // dwc3_msm_resume: GUSB2PHYCFG
  MMW (GCC_B + 0x39004, MMR (GCC_B + 0x39004) & ~1U);  // usb30_prim gdsc on
  MMW (GCC_B + 0x50018, MMR (GCC_B + 0x50018) & ~1U);  // usb3_phy gdsc on
  MMW (0x01FF1118ULL, 1);                             // tcsr_usb?_clkref_en
  MMW (0x01FF1108ULL, 1);                             // tcsr_usb?_clkref_en
  MMW (GCC_B + 0x39064, MMR (GCC_B + 0x39064) | 1U);  // phy_com_aux
  MMW (GCC_B + 0x39060, MMR (GCC_B + 0x39060) | 1U);  // phy_aux
  MMW (GCC_B + 0x39068, MMR (GCC_B + 0x39068) | 1U);  // phy_pipe
  gBS->Stall (1000);
  // PHY: EUD detect = 1 (the eusb2 phy "power" write), eUSB2 PHY BCR pulse, eUSB2 HS PHY init, QMP SS PHY init (+ wait for PCS ready)
  MMW (0x0C278000ULL, 1);
  MMW (GCC_B + 0x12000, 1);
  gBS->Stall (170);
  MMW (GCC_B + 0x12000, 0);
  for (I = 0; I < sizeof (mUrEusb2) / sizeof (mUrEusb2[0]); I++) {
    MMW (H + mUrEusb2[I][0], mUrEusb2[I][1]);
  }
  gBS->Stall (400);
  MMW (GCC_B + 0x50008, 1);                           // USB3_DP_PHY_PRIM_BCR assert
  MMW (GCC_B + 0x50000, 1);                           // USB3_PHY_PRIM_BCR assert
  gBS->Stall (10);
  MMW (GCC_B + 0x50000, 0);                           // deassert
  MMW (GCC_B + 0x50008, 0);
  for (I = 0; I < sizeof (mUrQmp) / sizeof (mUrQmp[0]); I++) {
    MMW (S + mUrQmp[I][0], mUrQmp[I][1]);
  }
  for (T = 0; T < 100; T++) {
    St = MMR (S + 0x1C14);
    if ((St & 1U) == 0) {
      break;
    }
    gBS->Stall (10000);
  }
  PL ("UR: PHYs initialised, QMP PCS_STATUS=0x%08x after %u polls%a", St, T, "\n");
  gBS->Stall (2000);

  // dwc3_core_soft_reset + dwc3_core_init + set_prtcap(device) + event buffer 0
  UrDwc3Reset (U);
  gBS->Stall (20000);
  MMW (U + 0xC2C0, 0x030E1002U);                      // GUSB3PIPECTL
  MMW (U + 0xC110, 0x00102000U);                      // GCTL
  UrEventBuffers (U, Ev0, Ev1);
  MMW (U + 0xC11C, 0x81001808U);                      // GUCTL1
  MMW (U + 0xC12C, 0x0D014802U);                      // GUCTL
  MMW (U + 0xC110, 0x00102000U);                      // set_prtcap(DEVICE)
  // dwc3_msm: pwr event ack, GSI rings, VBUS/session overrides, otg_start_peripheral
  MMW (U + 0xF8858, 0x4);
  UrNotifyRings (U, Ev1);
  MMW (Q + 0x10, 0x10100000U);                        // HS_PHY_CTRL: UTMI_OTG_VBUS_VALID | SESSVLD_SEL
  MMW (Q + 0x30, 0x01000000U);                        // SS_PHY_CTRL
  MMW (U + 0xF820C, 0x80000000U);
  UrDwc3Reset (U);
  gBS->Stall (1000);
  MMW (U + 0xF820C, 0);
  MMW (U + 0xF8808, 0x6);                             // QSCRATCH GENERAL_CFG
  MMW (U + 0xF8200, 0xFF);
  MMW (U + 0xF8204, 0xFF);
  MMW (U + 0xC200, 0x00102400U);                      // GUSB2PHYCFG
  MMW (U + 0xC11C, 0x81001808U);
  MMW (U + 0xF8858, 0xC);
  gBS->Stall (20000);
  // __dwc3_gadget_start: event buffers again, rings, IMOD, DCFG, DEVTEN, ep0 enable, RUN
  UrEventBuffers (U, Ev0, Ev1);
  UrNotifyRings (U, Ev1);
  MMW (U + 0xCA00, 0);
  MMW (U + 0xC10C, 0x00B00000U);
  MMW (U + 0xC700, 0x00200805U);
  MMW (U + 0xC700, 0x00A00805U);                      // DCFG: speed HS+SS, address 0, ... as Android
  MMW (U + 0xC708, 0x00000E57U);                      // DEVTEN
  MMW (U + 0xC720, 0x3);                              // DALEPENA: ep0 OUT/IN
  PL ("UR: before RUN: GCTL=0x%08x DCFG=0x%08x DCTL=0x%08x DSTS=0x%08x EVCNT0=%u%a", MMR (U + 0xC110), MMR (U + 0xC700), MMR (U + 0xC704), MMR (U + 0xC70C), MMR (U + 0xC40C), "\n");
  MMW (U + 0xC704, 0x80F00000U);                      // DCTL.RUN_STOP
  for (T = 0; T < 40; T++) {
    gBS->Stall (500000);
    J = MMR (U + 0xC70C);
    GeniCacheOp (Ev, 64);
    PL ("UR: t=%u.%u s DCTL=0x%08x DSTS=0x%08x (spd=%u link=%u) EVCNT0=%u GDBGLTSSM=0x%08x ev0=%08x %08x %08x %08x Q58=0x%08x Q10=0x%08x%a", T / 2, (T & 1) * 5, MMR (U + 0xC704), J, J & 7, (J >> 18) & 0xF,
        MMR (U + 0xC40C), MMR (U + 0xC164), Ev[0], Ev[1], Ev[2], Ev[3], MMR (Q + 0x58), MMR (Q + 0x10), "\n");
    if (T % 8 == 7) {
      Cc = (mMgD != NULL) ? RtrConnStatus (&W0, &W1) : 0xFFFFFFFFU;
      PL ("UR: UCSI connector status cci=0x%08x word0=0x%08x word1=0x%08x%a", Cc, W0, W1, "\n");
    }
  }
  UsbGoldenDump ("ur-after");
  MMW (U + 0xC704, 0x00F00000U);                      // stop
  if (PetEv != NULL) {
    gBS->SetTimer (PetEv, TimerCancel, 0);
  }
}

// USBPREP.TXT (normal boot, before Windows): bring the USB PHYs up the way Android does (clocks, TCSR clkrefs, BCR pulses, eUSB2 + QMP init) so that Windows' USB function stack starts on healthy PHYs.
STATIC VOID
UsbPhyPrep (VOID)
{
  CONST UINT64  U = 0x0A600000ULL, H = 0x088E3000ULL, S = 0x088E8000ULL;
  UINT32        I, T, St = 0;

  if ((MMR (GCC_B + 0x39004) & 0x80000000U) == 0) {
    PL ("UP: USB GDSC off, no PHY preparation%a", "\n");
    return;
  }
  PcEnsureMmio (U, 0x100000, "DWC3");
  PcEnsureMmio (H, 0x2000, "EUSB2");
  PcEnsureMmio (S, 0x3000, "QMP");
  PcEnsureMmio (0x0C278000ULL, 0x1000, "EUDDET");
  PcEnsureMmio (GCC_B, 0x80000, "GCC");
  PcEnsureMmio (0x01FF1000ULL, 0x1000, "TCSRCLKREF");
  MMW (GCC_B + 0x39004, MMR (GCC_B + 0x39004) & ~1U);
  MMW (GCC_B + 0x50018, MMR (GCC_B + 0x50018) & ~1U);
  MMW (0x01FF1118ULL, 1);
  MMW (0x01FF1108ULL, 1);
  MMW (GCC_B + 0x39064, MMR (GCC_B + 0x39064) | 1U);
  MMW (GCC_B + 0x39060, MMR (GCC_B + 0x39060) | 1U);
  MMW (GCC_B + 0x39068, MMR (GCC_B + 0x39068) | 1U);
  gBS->Stall (1000);
  MMW (0x0C278000ULL, 1);
  MMW (GCC_B + 0x12000, 1);
  gBS->Stall (170);
  MMW (GCC_B + 0x12000, 0);
  for (I = 0; I < sizeof (mUrEusb2) / sizeof (mUrEusb2[0]); I++) {
    MMW (H + mUrEusb2[I][0], mUrEusb2[I][1]);
  }
  gBS->Stall (400);
  MMW (GCC_B + 0x50008, 1);
  MMW (GCC_B + 0x50000, 1);
  gBS->Stall (10);
  MMW (GCC_B + 0x50000, 0);
  MMW (GCC_B + 0x50008, 0);
  for (I = 0; I < sizeof (mUrQmp) / sizeof (mUrQmp[0]); I++) {
    MMW (S + mUrQmp[I][0], mUrQmp[I][1]);
  }
  for (T = 0; T < 100; T++) {
    St = MMR (S + 0x1C14);
    if ((St & 1U) == 0) {
      break;
    }
    gBS->Stall (10000);
  }
  PL ("UP: USB PHYs prepared, QMP PCS_STATUS=0x%08x after %u polls%a", St, T, "\n");
}

STATIC VOID
DumpMemMap (VOID)
{
  UINTN                  Size = 0, Key, DSz;
  UINT32                 DVer;
  EFI_MEMORY_DESCRIPTOR  *Map = NULL, *D;
  UINTN                  N, K;
  UINT64                 High = 0;

  gBS->GetMemoryMap (&Size, NULL, &Key, &DSz, &DVer);
  Size += 8 * DSz;
  Map = AllocatePool (Size);
  if (Map == NULL || EFI_ERROR (gBS->GetMemoryMap (&Size, Map, &Key, &DSz, &DVer))) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] MEMMAP: GetMemoryMap failed\n"));
    return;
  }
  N = Size / DSz;
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] MEMMAP: %lu descriptors\n", (UINT64)N));
  for (K = 0; K < N; K++) {
    D = (EFI_MEMORY_DESCRIPTOR *)((UINT8 *)Map + K * DSz);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] MEMMAP t=%02u 0x%010lx pages=0x%lx attr=0x%lx\n", D->Type, D->PhysicalStart, D->NumberOfPages, D->Attribute));
    if (D->PhysicalStart + D->NumberOfPages * 4096 > High) {
      High = D->PhysicalStart + D->NumberOfPages * 4096;
    }
  }
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] MEMMAP: highest end 0x%lx\n", High));
  FreePool (Map);
}

// Writes Len bytes to a file on the volume MuChain was loaded from (created/truncated).
STATIC EFI_STATUS
SelfWriteBytes (IN CONST CHAR16 *Name, IN CONST VOID *Data, IN UINTN Len)
{
  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *Fs = NULL;
  EFI_FILE_PROTOCOL               *Root = NULL, *File = NULL;
  EFI_STATUS                      S;
  UINTN                           Done = 0, Chunk;

  if (mSelfVolume == NULL ||
      EFI_ERROR (gBS->HandleProtocol (mSelfVolume, &gEfiSimpleFileSystemProtocolGuid, (VOID **)&Fs)) ||
      EFI_ERROR (Fs->OpenVolume (Fs, &Root))) {
    return EFI_NOT_FOUND;
  }
  S = Root->Open (Root, &File, (CHAR16 *)Name, EFI_FILE_MODE_READ | EFI_FILE_MODE_WRITE | EFI_FILE_MODE_CREATE, 0);
  if (!EFI_ERROR (S)) {
    while (Done < Len && !EFI_ERROR (S)) {
      Chunk = Len - Done > 0x100000 ? 0x100000 : Len - Done;
      S = File->Write (File, &Chunk, (UINT8 *)Data + Done);
      Done += Chunk;
    }
    File->Flush (File);
    File->Close (File);
  }
  Root->Flush (Root);
  Root->Close (Root);
  return S;
}

// FDTSCAN.TXT (stage 0 of the Mu boot-menu idea, NEXT.md 0by): look for what ABL handed to this image in RAM.  Scans the memory the UEFI map calls free/loader/boot-services
// for (1) flattened device trees (magic D00DFEED; each is dumped to FDT<n>.DTB, with 'initrd' / 'androidboot' hints) and (2) the sentinels at the start of the test boot image's
// ramdisk and `second` blobs.  Result: FDTSCAN.TXT.  Only reads; never touches reserved / device memory.
#define FDTSCAN_MAX_DTB 6
STATIC CHAR8   *mScanTxt;
STATIC UINTN   mScanOut, mScanCap, mScanNDtb;

STATIC VOID
FdtScanRange (IN UINT64 P, IN UINT64 E)
{
  STATIC CONST CHAR8 RdTag[16]  = { 'R','M','9','R','D','-','S','E','N','T','I','N','E','L','-','A' };
  STATIC CONST CHAR8 SecTag[16] = { 'R','M','9','S','E','C','-','S','E','N','T','I','N','E','L','B' };

  for (; P + 16 <= E; P += 8) {
    UINT64 W0 = *(volatile UINT64 *)(UINTN)P;
    if ((UINT32)W0 == 0xEDFE0DD0U) {                       // FDT magic (big endian D00DFEED)
      UINT32 Tot = SwapBytes32 (*(UINT32 *)(UINTN)(P + 4));
      UINT32 Ver = SwapBytes32 (*(UINT32 *)(UINTN)(P + 20));
      if (Tot >= 0x400 && Tot <= 0x400000 && Ver >= 16 && Ver <= 17 && P + Tot <= E) {
        UINT32 I, Initrd = 0, Aboot = 0;
        for (I = 0; I + 24 < Tot; I += 4) {
          if (*(UINT32 *)(UINTN)(P + I) == 0x756E696C && CompareMem ((VOID *)(UINTN)(P + I), "linux,initrd-start", 18) == 0) { Initrd = 1; }
          if (*(UINT32 *)(UINTN)(P + I) == 0x646E6161 && CompareMem ((VOID *)(UINTN)(P + I), "androidboot.slot_suffix", 23) == 0) { Aboot = 1; }
        }
        mScanOut += AsciiSPrint (mScanTxt + mScanOut, mScanCap - mScanOut, "FDT at 0x%lx size 0x%x initrd=%u androidboot=%u\n", P, Tot, Initrd, Aboot);
        if (mScanNDtb < FDTSCAN_MAX_DTB && (Initrd != 0 || (P >= 0xA8000000ULL && P < 0xB8000000ULL))) {   // the final FDT (in the ABL handoff window) is dumped whatever the hint says (the property name may sit unaligned)
          CHAR16 Nm[16];
          UnicodeSPrint (Nm, sizeof (Nm), L"FDT%u.DTB", (UINT32)mScanNDtb);
          SelfWriteBytes (Nm, (VOID *)(UINTN)P, Tot);
          mScanNDtb++;
        }
      }
    }
    if ((W0 == *(CONST UINT64 *)RdTag && *(UINT64 *)(UINTN)(P + 8) == *(CONST UINT64 *)(RdTag + 8)) ||
        (W0 == *(CONST UINT64 *)SecTag && *(UINT64 *)(UINTN)(P + 8) == *(CONST UINT64 *)(SecTag + 8))) {
      mScanOut += AsciiSPrint (mScanTxt + mScanOut, mScanCap - mScanOut, "SENTINEL %c at 0x%lx\n", (W0 == *(CONST UINT64 *)RdTag) ? 'A' : 'B', P);
    }
    if (mScanOut + 256 > mScanCap) { break; }
  }
}

STATIC VOID
FdtScan (VOID)
{
  UINTN                  Size = 0, Key, DSz;
  UINT32                 DVer;
  EFI_MEMORY_DESCRIPTOR  *Map = NULL, *D;
  UINTN                  N, K;

  gBS->GetMemoryMap (&Size, NULL, &Key, &DSz, &DVer);
  Size += 8 * DSz;
  Map = AllocatePool (Size);
  mScanCap = 0x10000; mScanOut = 0; mScanNDtb = 0;
  mScanTxt = AllocateZeroPool (mScanCap);
  if (Map == NULL || mScanTxt == NULL || EFI_ERROR (gBS->GetMemoryMap (&Size, Map, &Key, &DSz, &DVer))) {
    return;
  }
  N = Size / DSz;
  mScanOut += AsciiSPrint (mScanTxt + mScanOut, mScanCap - mScanOut, "FDTSCAN: %lu descriptors (type start end attr)\n", (UINT64)N);
  for (K = 0; K < N; K++) {
    D = (EFI_MEMORY_DESCRIPTOR *)((UINT8 *)Map + K * DSz);
    mScanOut += AsciiSPrint (mScanTxt + mScanOut, mScanCap - mScanOut, "map t=%u 0x%lx-0x%lx a=0x%lx\n", (UINT32)D->Type, D->PhysicalStart, D->PhysicalStart + D->NumberOfPages * 4096, D->Attribute);
  }
  // pass 1: memory the map calls free / loader / boot services
  for (K = 0; K < N; K++) {
    D = (EFI_MEMORY_DESCRIPTOR *)((UINT8 *)Map + K * DSz);
    if (D->Type != EfiConventionalMemory && D->Type != EfiBootServicesCode && D->Type != EfiBootServicesData &&
        D->Type != EfiLoaderCode && D->Type != EfiLoaderData && D->Type != EfiACPIReclaimMemory) {
      continue;
    }
    FdtScanRange (D->PhysicalStart, D->PhysicalStart + D->NumberOfPages * 4096);
  }
  // pass 2: the window where ABL puts the kernel / final FDT / ramdisk in the Android boot (kernel 0xa8010000, FDT 0xb6eee000, initrd 0xb70ef000 - ordinary DDR)
  mScanOut += AsciiSPrint (mScanTxt + mScanOut, mScanCap - mScanOut, "window 0xA8000000-0xB8000000\n");
  FdtScanRange (0xA8000000ULL, 0xB8000000ULL);
  SelfWriteBytes (L"RDTAIL.BIN", (VOID *)(UINTN)0xB7FFC000ULL, 0x4000);   // last 16 KB of the handoff window: end of the ramdisk (bootconfig trailer?)
  mScanOut += AsciiSPrint (mScanTxt + mScanOut, mScanCap - mScanOut, "FDTSCAN: done\n");
  SelfWriteBytes (L"FDTSCAN.TXT", mScanTxt, mScanOut);
  FreePool (mScanTxt);
  FreePool (Map);
}

// ===== Android launch from Mu (stage 1 of the boot-menu idea, NEXT.md 0by/0bz) =====
// Booted through the slot-a launcher (boot header v2: Mu as the kernel + a dummy ramdisk), ABL has already built a complete Linux handoff: a final FDT (bootargs with all androidboot.*, memory map, ...)
// at ~0xB7CFE000 inside the ABL window 0xA8000000-0xB8000000.  This function reads the Android kernel Image (boot_b), the vendor ramdisk (vendor_boot_b) and the generic ramdisk (init_boot_b) straight from
// UFS, puts them in the window (kernel 0xA8000000, ramdisk 0xB0000000), patches the FDT (initrd-start/end, androidboot.slot_suffix _a -> _b) and - with Jump - hands over to the kernel (x0 = FDT).
// Log: ANDROID.LOG.
STATIC CHAR8   *mAlTxt;
STATIC UINTN   mAlOut, mAlCap;
#define ALOG(...) do { if (mAlOut + 300 < mAlCap) { mAlOut += AsciiSPrint (mAlTxt + mAlOut, mAlCap - mAlOut, __VA_ARGS__); } } while (0)

STATIC UINT32
FdtBe32 (IN CONST VOID *P)
{
  return SwapBytes32 (*(CONST UINT32 *)P);
}

// Pointer to the data of property Prop of /chosen (or NULL).
STATIC UINT8 *
FdtChosenProp (IN UINT8 *Fdt, IN CONST CHAR8 *Prop, OUT UINT32 *Len)
{
  UINT8   *S    = Fdt + FdtBe32 (Fdt + 8);
  UINT8   *End  = S + FdtBe32 (Fdt + 36);
  UINT8   *Strs = Fdt + FdtBe32 (Fdt + 12);
  UINT32  Depth = 0, Tok, L, NO;
  BOOLEAN InChosen = FALSE;

  while (S + 4 <= End) {
    Tok = FdtBe32 (S);
    S  += 4;
    if (Tok == 1) {
      CONST CHAR8 *Name = (CONST CHAR8 *)S;
      UINTN       NL    = AsciiStrLen (Name) + 1;
      S += (NL + 3) & ~(UINTN)3;
      Depth++;
      if (Depth == 2 && AsciiStrCmp (Name, "chosen") == 0) {
        InChosen = TRUE;
      }
    } else if (Tok == 2) {
      if (InChosen && Depth == 2) {
        InChosen = FALSE;
      }
      Depth--;
    } else if (Tok == 3) {
      L  = FdtBe32 (S);
      NO = FdtBe32 (S + 4);
      S += 8;
      if (InChosen && Depth == 2 && AsciiStrCmp ((CHAR8 *)(Strs + NO), Prop) == 0) {
        *Len = L;
        return S;
      }
      S += (L + 3) & ~3U;
    } else if (Tok == 4) {
      continue;
    } else {
      break;
    }
  }
  return NULL;
}

STATIC EFI_BLOCK_IO_PROTOCOL *
FindPartByName (IN CONST CHAR16 *Name)
{
  EFI_HANDLE            *Handles = NULL;
  UINTN                 Count = 0, I;
  EFI_BLOCK_IO_PROTOCOL *Found = NULL;

  if (EFI_ERROR (gBS->LocateHandleBuffer (ByProtocol, &gEfiPartitionInfoProtocolGuid, NULL, &Count, &Handles))) {
    return NULL;
  }
  for (I = 0; I < Count && Found == NULL; I++) {
    EFI_PARTITION_INFO_PROTOCOL *Pi = NULL;
    EFI_BLOCK_IO_PROTOCOL       *B  = NULL;
    if (EFI_ERROR (gBS->HandleProtocol (Handles[I], &gEfiPartitionInfoProtocolGuid, (VOID **)&Pi)) || Pi == NULL ||
        Pi->Type != PARTITION_TYPE_GPT || EFI_ERROR (gBS->HandleProtocol (Handles[I], &gEfiBlockIoProtocolGuid, (VOID **)&B)) || B == NULL) {
      continue;
    }
    if (StrCmp (Pi->Info.Gpt.PartitionName, Name) == 0) {
      Found = B;
    }
  }
  FreePool (Handles);
  return Found;
}

// Reads Bytes from the partition at byte offset Off into Dst (1 MB bounce chunks).
STATIC EFI_STATUS
PartRead (IN EFI_BLOCK_IO_PROTOCOL *B, IN UINT64 Off, IN UINTN Bytes, OUT UINT8 *Dst)
{
  UINTN      Bs = B->Media->BlockSize, Done = 0, Chunk;
  UINT8      *Tmp;
  EFI_STATUS S = EFI_SUCCESS;

  if ((Off % Bs) != 0) {
    return EFI_INVALID_PARAMETER;
  }
  Tmp = AllocatePool (0x100000);
  if (Tmp == NULL) {
    return EFI_OUT_OF_RESOURCES;
  }
  while (Done < Bytes && !EFI_ERROR (S)) {
    Chunk = Bytes - Done > 0x100000 ? 0x100000 : Bytes - Done;
    S = B->ReadBlocks (B, B->Media->MediaId, (Off + Done) / Bs, (Chunk + Bs - 1) / Bs * Bs, Tmp);
    if (!EFI_ERROR (S)) {
      CopyMem (Dst + Done, Tmp, Chunk);
      Done += Chunk;
    }
  }
  FreePool (Tmp);
  return S;
}

// Visual breadcrumbs for the Linux handoff: coloured blocks at the top of the panel (the SimpleFb framebuffer stays valid after ExitBootServices / MMU off).
STATIC BOOLEAN         mAndStub;
STATIC volatile UINT32 *mCrumbFb;
STATIC UINT32          mCrumbStride, mCrumbW;
STATIC UINT64          mCrumbBytes;

STATIC VOID
CrumbInit (VOID)
{
  EFI_GRAPHICS_OUTPUT_PROTOCOL *Gop = NULL;
  if (!EFI_ERROR (gBS->LocateProtocol (&gEfiGraphicsOutputProtocolGuid, NULL, (VOID **)&Gop)) && Gop != NULL && Gop->Mode != NULL) {
    mCrumbFb     = (volatile UINT32 *)(UINTN)Gop->Mode->FrameBufferBase;
    mCrumbStride = Gop->Mode->Info->PixelsPerScanLine;
    mCrumbW      = Gop->Mode->Info->HorizontalResolution;
    mCrumbBytes  = (UINT64)Gop->Mode->FrameBufferSize;
  }
}

STATIC VOID
Crumb (IN UINT32 Index, IN UINT32 Color)
{
  UINT32 X, Y;
  if (mCrumbFb == NULL) {
    return;
  }
  for (Y = 0; Y < 48; Y++) {
    for (X = Index * 64; X < Index * 64 + 56 && X < mCrumbW; X++) {
      mCrumbFb[(UINTN)Y * mCrumbStride + X] = Color;
    }
  }
}

// Last step of the Linux handoff, all in registers (no stack): turn the MMU and D-cache off, clean + invalidate the whole D-cache by set/way (stale dirty lines of Mu's stack would otherwise be written back over
// Linux's memory later), invalidate the I-cache, branch to the entry with x0 = FDT.  Calling ArmDisableDataCache () from C and then returning into a frame whose stack lines were still dirty in the cache hung here.
__attribute__ ((naked, noreturn)) STATIC VOID
JumpToKernel (IN UINT64 Fdt, IN UINT64 Entry)
{
  __asm__ volatile (
    "mov x19, x0\n"
    "mov x20, x1\n"
    "mov x4, #5\n"                    // SCTLR.M | SCTLR.C
    "mrs x2, CurrentEL\n"
    "cmp x2, #8\n"
    "b.eq 1f\n"
    "mrs x3, sctlr_el1\n"
    "bic x3, x3, x4\n"
    "msr sctlr_el1, x3\n"
    "b 2f\n"
    "1:\n"
    "mrs x3, sctlr_el2\n"
    "bic x3, x3, x4\n"
    "msr sctlr_el2, x3\n"
    "2:\n"
    "isb\n"
    "ic iallu\n"
    "dsb sy\n"
    "isb\n"
    "mrs x0, clidr_el1\n"
    "ubfx x1, x0, #24, #3\n"          // LoC
    "cbz x1, 9f\n"
    "mov x2, #0\n"                    // x2 = level << 1
    "3:\n"
    "add x3, x2, x2, lsr #1\n"        // level * 3
    "lsr x3, x0, x3\n"
    "and x3, x3, #7\n"
    "cmp x3, #2\n"
    "b.lt 8f\n"                       // no data / unified cache at this level
    "msr csselr_el1, x2\n"
    "isb\n"
    "mrs x4, ccsidr_el1\n"
    "and x5, x4, #7\n"
    "add x5, x5, #4\n"                // line shift
    "ubfx x6, x4, #3, #10\n"          // max way
    "ubfx x7, x4, #13, #15\n"         // max set
    "clz w8, w6\n"                    // way shift
    "4:\n"
    "mov x9, x7\n"
    "5:\n"
    "lsl x10, x6, x8\n"
    "lsl x11, x9, x5\n"
    "orr x10, x10, x11\n"
    "orr x10, x10, x2\n"
    "dc cisw, x10\n"
    "subs x9, x9, #1\n"
    "b.ge 5b\n"
    "subs x6, x6, #1\n"
    "b.ge 4b\n"
    "8:\n"
    "add x2, x2, #2\n"
    "lsr x3, x2, #1\n"
    "cmp x3, x1\n"
    "b.lt 3b\n"
    "9:\n"
    "dsb sy\n"
    "isb\n"
    "ic iallu\n"
    "dsb sy\n"
    "isb\n"
    "mov x0, x19\n"
    "mov x1, #0\n"
    "mov x2, #0\n"
    "mov x3, #0\n"
    "br x20\n"
  );
}

// Clean + invalidate the whole data cache by set/way (CacheMaintenanceLib's WriteBackInvalidateDataCache asserts on ARM): needed before the MMU / D-cache are turned off for a Linux handoff.
STATIC VOID
FlushDcacheAll (VOID)
{
  UINT64 Clidr, Level, Ccsidr, Sets, Ways, LineShift, WayShift, Set, Way, Val;

  __asm__ volatile ("dsb sy" ::: "memory");
  __asm__ volatile ("mrs %0, clidr_el1" : "=r" (Clidr));
  for (Level = 0; Level < ((Clidr >> 24) & 7); Level++) {
    if (((Clidr >> (Level * 3)) & 7) < 2) {
      continue;                                   // no data / unified cache at this level
    }
    Val = Level << 1;
    __asm__ volatile ("msr csselr_el1, %0" :: "r" (Val));
    __asm__ volatile ("isb");
    __asm__ volatile ("mrs %0, ccsidr_el1" : "=r" (Ccsidr));
    LineShift = (Ccsidr & 7) + 4;
    Ways      = ((Ccsidr >> 3) & 0x3FF) + 1;
    Sets      = ((Ccsidr >> 13) & 0x7FFF) + 1;
    WayShift  = (Ways > 1) ? (UINT64)__builtin_clz ((UINT32)(Ways - 1)) : 32;
    for (Way = 0; Way < Ways; Way++) {
      for (Set = 0; Set < Sets; Set++) {
        Val = (Way << WayShift) | (Set << LineShift) | (Level << 1);
        __asm__ volatile ("dc cisw, %0" :: "r" (Val) : "memory");
      }
    }
  }
  __asm__ volatile ("dsb sy" ::: "memory");
  __asm__ volatile ("isb");
}

STATIC VOID
AndroidLaunch (IN EFI_HANDLE ImageHandle, IN BOOLEAN Jump)
{
  EFI_BLOCK_IO_PROTOCOL *Bk, *Bv, *Bi;
  UINT8                 Hdr[4096];
  UINT8                 *Fdt = NULL, *K = NULL, *R = NULL;
  UINT32                KSz, VSz, ISz;
  UINT64                P;
  UINTN                 RSz;
  UINT32                L = 0;
  UINT8                 *Pr;
  EFI_STATUS            S;

  mAlCap = 0x4000;
  mAlOut = 0;
  mAlTxt = AllocateZeroPool (mAlCap);
  if (mAlTxt == NULL) {
    return;
  }
  ALOG ("ANDROID: Jump=%u\n", (UINT32)Jump);
  // 1. the final FDT ABL built for this boot: page aligned, FDT magic, has /chosen/linux,initrd-start
  for (P = 0xB0000000ULL; P < 0xB8000000ULL && Fdt == NULL; P += 0x1000) {
    if (*(UINT32 *)(UINTN)P == 0xEDFE0DD0U) {
      UINT32 Tot = FdtBe32 ((VOID *)(UINTN)(P + 4));
      if (Tot >= 0x60000 && Tot <= 0x200000 && FdtBe32 ((VOID *)(UINTN)(P + 20)) == 17 && FdtChosenProp ((UINT8 *)(UINTN)P, "linux,initrd-start", &L) != NULL) {
        Fdt = (UINT8 *)(UINTN)P;
        ALOG ("FDT at 0x%lx size 0x%x\n", P, Tot);
      }
    }
  }
  if (Fdt == NULL) {
    ALOG ("no FDT found\n");
    goto Done;
  }
  // 2. partitions
  Bk = FindPartByName (L"boot_b");
  Bv = FindPartByName (L"vendor_boot_b");
  Bi = FindPartByName (L"init_boot_b");
  ALOG ("partitions: boot_b=%p vendor_boot_b=%p init_boot_b=%p\n", Bk, Bv, Bi);
  if (Bk == NULL || Bv == NULL || Bi == NULL) {
    goto Done;
  }
  if (EFI_ERROR (PartRead (Bk, 0, 4096, Hdr)) || CompareMem (Hdr, "ANDROID!", 8) != 0) {
    ALOG ("boot_b header bad\n");
    goto Done;
  }
  KSz = *(UINT32 *)(Hdr + 8);
  if (EFI_ERROR (PartRead (Bv, 0, 4096, Hdr)) || CompareMem (Hdr, "VNDRBOOT", 8) != 0) {
    ALOG ("vendor_boot_b header bad\n");
    goto Done;
  }
  VSz = *(UINT32 *)(Hdr + 24);
  if (EFI_ERROR (PartRead (Bi, 0, 4096, Hdr)) || CompareMem (Hdr, "ANDROID!", 8) != 0) {
    ALOG ("init_boot_b header bad\n");
    goto Done;
  }
  ISz = *(UINT32 *)(Hdr + 12);
  ALOG ("kernel %u vendor ramdisk %u init_boot ramdisk %u\n", KSz, VSz, ISz);
  if (KSz < 0x100000 || KSz > 0x4000000 || VSz < 0x10000 || VSz > 0x2000000 || ISz < 0x1000 || ISz > 0x1000000) {
    goto Done;
  }
  // 3. load
  RSz = (UINTN)VSz + ISz;
  K   = AllocatePages ((KSz + 4095) / 4096);
  R   = AllocatePages ((RSz + 4095) / 4096);
  if (K == NULL || R == NULL) {
    ALOG ("alloc failed\n");
    goto Done;
  }
  S = PartRead (Bk, 4096, KSz, K);
  ALOG ("read kernel: %r  head %02x%02x%02x%02x magic@56=%c%c%c%c\n", S, K[0], K[1], K[2], K[3], K[56], K[57], K[58], K[59]);
  if (EFI_ERROR (S)) {
    goto Done;
  }
  S = PartRead (Bv, 4096, VSz, R);
  ALOG ("read vendor ramdisk: %r\n", S);
  if (EFI_ERROR (S)) {
    goto Done;
  }
  S = PartRead (Bi, 4096, ISz, R + VSz);
  ALOG ("read init_boot ramdisk: %r\n", S);
  if (EFI_ERROR (S)) {
    goto Done;
  }
  // 4. place in the ABL window (ordinary DDR; nothing else uses it any more)
  CopyMem ((VOID *)(UINTN)0xA8000000ULL, K, KSz);
  CopyMem ((VOID *)(UINTN)0xB0000000ULL, R, RSz);
  ALOG ("placed: kernel @0xA8000000 (%u B), ramdisk @0xB0000000 (%lu B); verify %u/%u\n", KSz, (UINT64)RSz,
        (UINT32)(CompareMem ((VOID *)(UINTN)0xA8000000ULL, K, KSz) == 0), (UINT32)(CompareMem ((VOID *)(UINTN)0xB0000000ULL, R, RSz) == 0));
  // 5. patch the FDT: initrd properties (u64 big endian) and the slot suffix in bootargs
  Pr = FdtChosenProp (Fdt, "linux,initrd-start", &L);
  if (Pr != NULL && L == 8) {
    *(UINT32 *)(Pr)     = 0;
    *(UINT32 *)(Pr + 4) = SwapBytes32 (0xB0000000U);
  }
  Pr = FdtChosenProp (Fdt, "linux,initrd-end", &L);
  if (Pr != NULL && L == 8) {
    *(UINT32 *)(Pr)     = 0;
    *(UINT32 *)(Pr + 4) = SwapBytes32 (0xB0000000U + (UINT32)RSz);
  }
  Pr = FdtChosenProp (Fdt, "bootargs", &L);
  if (Pr != NULL) {
    UINT32 I;
    for (I = 0; I + 26 <= L; I++) {
      if (CompareMem (Pr + I, "androidboot.slot_suffix=_a", 26) == 0) {
        Pr[I + 25] = 'b';
        ALOG ("bootargs: slot_suffix patched to _b\n");
        break;
      }
    }
    ALOG ("bootargs (%u): %a\n", L, (CHAR8 *)Pr);
  } else {
    ALOG ("no bootargs\n");
  }
  if (!Jump) {
    goto Done;
  }
  if (Jump && mAndStub) {      // bisect: replace the kernel by a framebuffer-fill stub
    UINT32 *Code = (UINT32 *)(UINTN)0xA8000000ULL;
    UINT64 Fb, Cnt;
    CrumbInit ();
    Fb  = (UINT64)(UINTN)mCrumbFb;
    Cnt = mCrumbBytes / 4;
    Code[0]  = 0xD2800001U | ((UINT32)(Fb & 0xFFFF) << 5);                    // movz x1, fb[15:0]
    Code[1]  = 0xF2A00001U | ((UINT32)((Fb >> 16) & 0xFFFF) << 5);            // movk x1, fb[31:16], lsl 16
    Code[2]  = 0xF2C00001U | ((UINT32)((Fb >> 32) & 0xFFFF) << 5);            // movk x1, fb[47:32], lsl 32
    Code[3]  = 0xD2800002U | ((UINT32)(Cnt & 0xFFFF) << 5);                   // movz x2, count[15:0]
    Code[4]  = 0xF2A00002U | ((UINT32)((Cnt >> 16) & 0xFFFF) << 5);           // movk x2, count[31:16], lsl 16
    Code[5]  = 0x52801FE3U | 0;                                               // movz w3, #0x00FF
    Code[6]  = 0x72A01FE3U | 0;                                               // movk w3, #0x00FF, lsl 16  -> 0x00FF00FF
    Code[7]  = 0xB8004423U;                                                   // loop: str w3, [x1], #4
    Code[8]  = 0xF1000442U;                                                   // subs x2, x2, #1
    Code[9]  = 0x54FFFFC1U;                                                   // b.ne loop
    Code[10] = 0xD5033F9FU;                                                   // dsb sy
    Code[11] = 0x14000000U;                                                   // b .
    ALOG ("ANDSTUB: fb 0x%lx, %lu words\n", Fb, Cnt);
  }
  // 6. hand over: write the log first, leave boot services, MMU / caches off, branch to the kernel Image with x0 = FDT
  CrumbInit ();
  Crumb (0, 0x00FFFFFF);                      // white: about to leave boot services
  SelfWriteBytes (L"ANDROID.LOG", mAlTxt, mAlOut);
  {
    UINTN                 Size = 0, Key, DSz;
    UINT32                DVer;
    EFI_MEMORY_DESCRIPTOR *Map;

    gBS->GetMemoryMap (&Size, NULL, &Key, &DSz, &DVer);
    Size += 8 * DSz;
    Map = AllocatePool (Size);
    {
      ARM_SMC_ARGS Wa = { 0 };
      Wa.Arg0 = 0x86000005U;   // GH_WDT_CONTROL
      Wa.Arg1 = 2;             // DISABLE (Linux's own watchdog driver takes over; Mu's 31 s watchdog would bite during the long Android boot)
      ArmCallSmc (&Wa);
      ALOG ("GH_WDT disable ret=%ld\n", (INT64)Wa.Arg0);
    }
    if (Map == NULL || EFI_ERROR (gBS->GetMemoryMap (&Size, Map, &Key, &DSz, &DVer)) || EFI_ERROR (gBS->ExitBootServices (ImageHandle, Key))) {
      Crumb (1, 0x00FF0000);                   // red: ExitBootServices failed
      return;
    }
  }
  Crumb (1, 0x0000FF00);                       // green: boot services exited
  ArmDisableInterrupts ();
  FlushDcacheAll ();
  Crumb (2, 0x0000FF00);                       // caches flushed
  Crumb (3, 0x0000FF00);                       // about to run the trampoline (MMU / D-cache off, set/way flush, branch)
  JumpToKernel ((UINT64)(UINTN)Fdt, ((UINT64)0xA8000000ULL));
  CpuDeadLoop ();
Done:
  SelfWriteBytes (L"ANDROID.LOG", mAlTxt, mAlOut);
}

STATIC VOID
UfsProbe (VOID)
{
  DumpMemMap ();
  UfsProbeOne (0x1D84000ULL, 0x15000, TRUE);    // UFS HC (DSDT UFS0: MMIO 0x1D84000 len 0x15000)
  UfsProbeOne (0x1D87000ULL, 0x1000,  FALSE);   // UFS PHY area, descriptor only
  UfsProbeOne (0x1D90000ULL, 0x1000,  FALSE);   // UFS ICE area, descriptor only
  if (SelfFileExists (L"\\WPTEST.TXT") && SelfFileExists (L"\\NOBOOT.TXT")) {
    UfsWpTest (0x1D84000ULL);
  }
}

STATIC VOID
DumpProtocolsOnDisks (VOID)
{
  EFI_HANDLE *Handles = NULL;
  UINTN      Count = 0, Index;

  if (EFI_ERROR (gBS->LocateHandleBuffer (ByProtocol, &gEfiBlockIoProtocolGuid, NULL, &Count, &Handles))) {
    return;
  }
  for (Index = 0; Index < Count; Index++) {
    EFI_BLOCK_IO_PROTOCOL *B = NULL;
    EFI_GUID              **Guids = NULL;
    UINTN                 N = 0, K;

    if (EFI_ERROR (gBS->HandleProtocol (Handles[Index], &gEfiBlockIoProtocolGuid, (VOID **)&B)) || B == NULL ||
        B->Media == NULL || B->Media->LogicalPartition) {
      continue;
    }
    if (!EFI_ERROR (gBS->ProtocolsPerHandle (Handles[Index], &Guids, &N)) && Guids != NULL) {
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] disk handle %p (last=0x%lx) has %lu protocols:\n", Handles[Index], (UINT64)B->Media->LastBlock, (UINT64)N));
      for (K = 0; K < N; K++) {
        DEBUG ((DEBUG_ERROR, "[MUCHAIN]    proto %g\n", Guids[K]));
      }
      FreePool (Guids);
    }
  }
  FreePool (Handles);

  // handles carrying the standard EDK2 UFS interfaces?
  {
    STATIC EFI_GUID UfsPassThru   = { 0x1d3de7f0, 0x0807, 0x424f, { 0xaa, 0x69, 0x11, 0xa5, 0x4e, 0x19, 0xa4, 0x6f } };
    STATIC EFI_GUID UfsDevConfig  = { 0xb30dfeed, 0x947f, 0x4396, { 0xb1, 0x5a, 0xdf, 0xbd, 0xb9, 0x16, 0xdc, 0x24 } };
    STATIC EFI_GUID UfsHc         = { 0xebd3a5d9, 0x1b59, 0x4f10, { 0x84, 0x4a, 0x9c, 0x5c, 0x6b, 0x8a, 0x4c, 0x90 } };
    VOID *Pt = NULL;
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] UfsPassThru: %r  UfsDeviceConfig: %r  (UfsHc guess: %r)\n",
            gBS->LocateProtocol (&UfsPassThru, NULL, &Pt), gBS->LocateProtocol (&UfsDevConfig, NULL, &Pt),
            gBS->LocateProtocol (&UfsHc, NULL, &Pt)));
  }
}

STATIC BOOLEAN
SelfFileExists (IN CONST CHAR16 *Name)
{
  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *Fs = NULL;
  EFI_FILE_PROTOCOL               *Root = NULL, *File = NULL;
  BOOLEAN                         Found = FALSE;

  if (mSelfVolume != NULL &&
      !EFI_ERROR (gBS->HandleProtocol (mSelfVolume, &gEfiSimpleFileSystemProtocolGuid, (VOID **)&Fs)) &&
      !EFI_ERROR (Fs->OpenVolume (Fs, &Root))) {
    if (!EFI_ERROR (Root->Open (Root, &File, (CHAR16 *)Name, EFI_FILE_MODE_READ, 0))) {
      File->Close (File);
      Found = TRUE;
    }
    Root->Close (Root);
  }
  return Found;
}

// First byte of a file on the volume MuChain was loaded from, or -1 when it cannot be read.
STATIC INTN
SelfFirstByte (IN CONST CHAR16 *Name)
{
  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *Fs = NULL;
  EFI_FILE_PROTOCOL               *Root = NULL, *File = NULL;
  INTN                            Byte = -1;
  UINT8                           B;
  UINTN                           Sz = 1;

  if (mSelfVolume != NULL &&
      !EFI_ERROR (gBS->HandleProtocol (mSelfVolume, &gEfiSimpleFileSystemProtocolGuid, (VOID **)&Fs)) &&
      !EFI_ERROR (Fs->OpenVolume (Fs, &Root))) {
    if (!EFI_ERROR (Root->Open (Root, &File, (CHAR16 *)Name, EFI_FILE_MODE_READ, 0))) {
      if (!EFI_ERROR (File->Read (File, &Sz, &B)) && Sz == 1) {
        Byte = B;
      }
      File->Close (File);
    }
    Root->Close (Root);
  }
  return Byte;
}

// Deletes a file on the volume MuChain was loaded from.  TRUE only when the file existed and the delete succeeded.
STATIC BOOLEAN
SelfDeleteFile (IN CONST CHAR16 *Name)
{
  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *Fs = NULL;
  EFI_FILE_PROTOCOL               *Root = NULL, *File = NULL;
  BOOLEAN                         Done = FALSE;

  if (mSelfVolume != NULL &&
      !EFI_ERROR (gBS->HandleProtocol (mSelfVolume, &gEfiSimpleFileSystemProtocolGuid, (VOID **)&Fs)) &&
      !EFI_ERROR (Fs->OpenVolume (Fs, &Root))) {
    if (!EFI_ERROR (Root->Open (Root, &File, (CHAR16 *)Name, EFI_FILE_MODE_READ | EFI_FILE_MODE_WRITE, 0))) {
      Done = (File->Delete (File) == EFI_SUCCESS);   // Delete() closes the handle in every case
    }
    Root->Close (Root);
  }
  return Done;
}

STATIC EFI_STATUS
FindBootMgr (OUT EFI_DEVICE_PATH_PROTOCOL **Path, IN EFI_HANDLE Self)
{
  EFI_HANDLE                       *Handles = NULL;
  UINTN                            Count = 0;
  UINTN                            Index;
  EFI_STATUS                       Status;
  CONST CHAR16                     *Target = L"\\EFI\\Microsoft\\Boot\\bootmgfw.efi";

  Status = gBS->LocateHandleBuffer (ByProtocol, &gEfiSimpleFileSystemProtocolGuid, NULL, &Count, &Handles);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] SimpleFileSystem handles: %r count=%lu\n", Status, (UINT64)Count));
  if (EFI_ERROR (Status)) {
    return Status;
  }
  for (Index = 0; Index < Count; Index++) {
    EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *Fs = NULL;
    EFI_FILE_PROTOCOL               *Root = NULL;
    EFI_FILE_PROTOCOL               *File = NULL;
    CHAR16                          *Text;

    Text = ConvertDevicePathToText (DevicePathFromHandle (Handles[Index]), FALSE, FALSE);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] vol[%lu] %s\n", (UINT64)Index, Text != NULL ? Text : L"?"));
    if (Text != NULL) {
      FreePool (Text);
    }
    if (EFI_ERROR (gBS->HandleProtocol (Handles[Index], &gEfiSimpleFileSystemProtocolGuid, (VOID **)&Fs))) {
      continue;
    }
    if (EFI_ERROR (Fs->OpenVolume (Fs, &Root))) {
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] vol[%lu] OpenVolume failed\n", (UINT64)Index));
      continue;
    }
    Status = Root->Open (Root, &File, (CHAR16 *)Target, EFI_FILE_MODE_READ, 0);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] vol[%lu] open bootmgfw.efi: %r\n", (UINT64)Index, Status));
    if (!EFI_ERROR (Status)) {
      File->Close (File);
      Root->Close (Root);
      *Path = FileDevicePath (Handles[Index], Target);
      FreePool (Handles);
      return (*Path != NULL) ? EFI_SUCCESS : EFI_OUT_OF_RESOURCES;
    }
    Root->Close (Root);
  }
  FreePool (Handles);
  return EFI_NOT_FOUND;
}


// ---------------------------------------------------------------------------------------------------------------------------------------------------------
// ItsTest (NOBOOT + \ITSTEST.TXT): the same GICv3 LPI path Linux uses, built from scratch in firmware context, without Windows.  Question: does an ITS INT command turn into an LPI that the CPU
// interface of this PE acknowledges (ICC_IAR1_EL1)?  In Windows the ITS accepts the commands and every table looks right, but the LPI never shows up.
// ---------------------------------------------------------------------------------------------------------------------------------------------------------
#define ITS_BASE    0x17140000ULL
#define GICR_BASE   0x17180000ULL
#define GICR_STRIDE 0x40000ULL
#define M64R(a)     (*(volatile UINT64 *)(UINTN)(a))
#define M64W(a, v)  (*(volatile UINT64 *)(UINTN)(a) = (UINT64)(v))

STATIC CHAR8  mItsLog[16000];
STATIC UINTN  mItsLogLen;
STATIC VOID ItsLogF (IN CONST CHAR8 *Fmt, ...)
{
  VA_LIST  Ap;
  CHAR8    Line[300];
  UINTN    L;
  VA_START (Ap, Fmt);
  AsciiVSPrint (Line, sizeof (Line), Fmt, Ap);
  VA_END (Ap);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] %a", Line));
  L = AsciiStrLen (Line);
  if (mItsLogLen + L < sizeof (mItsLog) - 1) {
    CopyMem (mItsLog + mItsLogLen, Line, L);
    mItsLogLen += L;
    mItsLog[mItsLogLen] = 0;
  }
}

STATIC UINT64 ItsReadIar1 (VOID) { UINT64 V; __asm__ volatile ("mrs %0, S3_0_C12_C12_0" : "=r" (V)); return V; }
STATIC VOID   ItsWriteEoir1 (UINT64 V) { __asm__ volatile ("msr S3_0_C12_C12_1, %0" :: "r" (V)); }
STATIC UINT64 ItsReadPmr (VOID) { UINT64 V; __asm__ volatile ("mrs %0, S3_0_C4_C6_0" : "=r" (V)); return V; }
STATIC VOID   ItsWritePmr (UINT64 V) { __asm__ volatile ("msr S3_0_C4_C6_0, %0" :: "r" (V)); }
STATIC UINT64 ItsReadIgrpen1 (VOID) { UINT64 V; __asm__ volatile ("mrs %0, S3_0_C12_C12_7" : "=r" (V)); return V; }
STATIC UINT64 ItsReadSre (VOID) { UINT64 V; __asm__ volatile ("mrs %0, S3_0_C12_C12_5" : "=r" (V)); return V; }
STATIC UINT64 ItsReadEl (VOID) { UINT64 V; __asm__ volatile ("mrs %0, CurrentEL" : "=r" (V)); return V; }
STATIC UINT64 ItsReadIcCtlr (VOID) { UINT64 V; __asm__ volatile ("mrs %0, S3_0_C12_C12_4" : "=r" (V)); return V; }
STATIC UINT64 ItsReadBpr1 (VOID) { UINT64 V; __asm__ volatile ("mrs %0, S3_0_C12_C12_3" : "=r" (V)); return V; }
STATIC UINT64 ItsReadRpr (VOID) { UINT64 V; __asm__ volatile ("mrs %0, S3_0_C12_C11_3" : "=r" (V)); return V; }
STATIC UINT64 ItsReadMpidr (VOID) { UINT64 V; __asm__ volatile ("mrs %0, mpidr_el1" : "=r" (V)); return V; }

STATIC VOID *ItsAlloc (UINTN Bytes, UINTN Align)
{
  EFI_PHYSICAL_ADDRESS  A = 0;
  UINTN                 Pages = EFI_SIZE_TO_PAGES (Bytes + Align);
  if (EFI_ERROR (gBS->AllocatePages (AllocateAnyPages, EfiBootServicesData, Pages, &A))) {
    return NULL;
  }
  A = (A + Align - 1) & ~((EFI_PHYSICAL_ADDRESS)Align - 1);
  ZeroMem ((VOID *)(UINTN)A, Bytes);
  return (VOID *)(UINTN)A;
}

STATIC VOID *ItsAllocAt (UINT64 Pa, UINTN Bytes)
{
  EFI_PHYSICAL_ADDRESS  A = Pa;
  UINTN                 Pages = EFI_SIZE_TO_PAGES (Bytes);
  EFI_STATUS            St = gBS->AllocatePages (AllocateAddress, EfiBootServicesData, Pages, &A);
  if (EFI_ERROR (St)) {
    ItsLogF ("ITSTEST: cannot allocate %lx: %r\n", Pa, St);
    return NULL;
  }
  ZeroMem ((VOID *)(UINTN)A, Bytes);
  return (VOID *)(UINTN)A;
}

STATIC UINT32 mItsQw;     // CWRITER byte offset
STATIC UINT8  *mItsQ;

STATIC VOID ItsCmd (UINT64 D0, UINT64 D1, UINT64 D2, UINT64 D3)
{
  volatile UINT64 *C = (volatile UINT64 *)(mItsQ + mItsQw);
  C[0] = D0; C[1] = D1; C[2] = D2; C[3] = D3;
  mItsQw = (mItsQw + 32) & 0xFFF;
}

STATIC VOID ItsKick (CONST CHAR8 *Tag)
{
  UINT32 I;
  WriteBackInvalidateDataCacheRange (mItsQ, 0x1000);
  M64W (ITS_BASE + 0x88, mItsQw);
  for (I = 0; I < 2000; I++) {
    if (MMR (ITS_BASE + 0x90) == mItsQw) {
      break;
    }
    gBS->Stall (50);
  }
  ItsLogF ("ITS %a: CWRITER=%x CREADR=%x%a\n", Tag, mItsQw, MMR (ITS_BASE + 0x90), (MMR (ITS_BASE + 0x90) == mItsQw) ? "" : "  (STALLED)");
}


// REGDUMP: GIC register dump (same offsets as rpfix.ps1's RegDump) so that the Windows state can be diffed against this clean-room state.  Logged before every read so that a hang names its register.
STATIC VOID ItsProg (CONST CHAR8 *Grp, UINT32 Off)
{
  STATIC CHAR8 Tmp[6200];      // ITSPROG: the log so far plus "reading <group> <offset>", written before the read: a hang names its register
  UINTN        L = AsciiStrLen (mItsLog);
  CopyMem (Tmp, mItsLog, L);
  AsciiSPrint (Tmp + L, sizeof (Tmp) - L, "\nREADING %a %x\n", Grp, Off);
  WriteTestFile (L"\\ITSRES.TXT", Tmp);
}

STATIC VOID ItsRegDump (CONST CHAR8 *Tag)
{
  STATIC CONST UINT32 Rd[] = {0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20, 0x24, 0x28, 0x2C, 0x30, 0x34, 0x38, 0x3C, 0x40, 0x44, 0x48, 0x4C, 0x50, 0x54, 0x58, 0x5C, 0x60, 0x64, 0x68, 0x6C, 0x70, 0x74, 0x78, 0x7C, 0xC0, 0xFFD0, 0xFFD4, 0xFFD8, 0xFFDC, 0xFFE0, 0xFFE4, 0xFFE8, 0xFFEC, 0xFFF0, 0xFFF4, 0xFFF8, 0xFFFC};
  STATIC CONST UINT32 Sg[] = {0x80, 0xD00, 0xD04, 0xD08, 0xD0C, 0xF00, 0xF04, 0xF08};
  STATIC CONST UINT32 Gd[] = {0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20, 0x24, 0x28, 0x2C, 0x30, 0x34, 0x38, 0x3C, 0x40, 0x44, 0xFFD0, 0xFFD4, 0xFFD8, 0xFFDC, 0xFFE0, 0xFFE4, 0xFFE8, 0xFFEC, 0xFFF0, 0xFFF4, 0xFFF8, 0xFFFC};
  STATIC CONST UINT32 It[] = {0x00, 0x04, 0x08, 0x80, 0x84, 0x88, 0x8C, 0x90, 0x94, 0x100, 0x104, 0x108, 0x10C, 0x110, 0x114};
  UINT32 I;
  CHAR8  Line[400];
  UINTN  L = 0;
  ItsLogF ("REGDUMP %a GICR0 RD:", Tag);
  for (I = 0; I < ARRAY_SIZE (Rd); I++) {
    ItsProg ("RD", Rd[I]);
    ItsLogF (" %x=%x", Rd[I], MMR (GICR_BASE + Rd[I]));
  }
  ItsLogF ("\nREGDUMP %a GICR0 SGI:", Tag);
  for (I = 0; I < ARRAY_SIZE (Sg); I++) {
    ItsProg ("SGI", Sg[I]);
    ItsLogF (" %x=%x", Sg[I], MMR (GICR_BASE + 0x10000 + Sg[I]));
  }
  ItsLogF ("\nREGDUMP %a GICD:", Tag);
  for (I = 0; I < ARRAY_SIZE (Gd); I++) {
    ItsProg ("GICD", Gd[I]);
    ItsLogF (" %x=%x", Gd[I], MMR (0x17100000ULL + Gd[I]));
  }
  ItsLogF ("\nREGDUMP %a ITS:", Tag);
  for (I = 0; I < ARRAY_SIZE (It); I++) {
    if (mBhiMode && It[I] == 0x114) continue;   // ITS+0x114 hangs the bus now and then (BHI runs, 2026-10-31)
    ItsProg ("ITS", It[I]);
    ItsLogF (" %x=%x", It[I], MMR (ITS_BASE + It[I]));
  }
  ItsLogF ("\n");
  (VOID)Line; (VOID)L;
}

// ---------------------------------------------------------------------------------------------------------------------------------------------------------
// BHI test (2026-10-30; NOBOOT + \BHITEST.TXT; ItsTestBody calls it from inside PcieProbe while the link is up).  The ITS INT command of ItsTest skips the path a real MSI takes: the endpoint's write to GITS_TRANSLATER
// (DeviceID from the SMMU stream / PARF BDF->SID, device table, ITT, collection).  To make the CHIP raise an MSI without a driver: the PBL accepts an SBL image through BHI (BAR0 + BHIOFF) and signals the host when it has
// taken it (BHI_INTVEC = MSI vector 0 -> EventID 0 -> LPI 0x2010 in ItsTest's tables).  The image is the first 256 KB of wlanfw20.mbn, the size Windows hands to BHI (IMGSIZE=0x40000).
// ---------------------------------------------------------------------------------------------------------------------------------------------------------
STATIC UINT8   *mBhiImg;
STATIC UINTN   mBhiImgSize;
// DeviceID hunt (BHI mode): the chip's MSI is a write to GITS_TRANSLATER whose DeviceID comes from the PCIe controller / SMMU side, not from software.  If it is not 0x1401 the ITS drops it silently.  Map event 0 of these
// DeviceIDs to LPI 0x2020 + index; the LPI that gets acknowledged tells the DeviceID the chip really arrives with.
#define BHI_NCAND 10
STATIC CONST UINT32 mBhiCand[BHI_NCAND] = { 0x0000, 0x0100, 0x0400, 0x0401, 0x1000, 0x1100, 0x1300, 0x1400, 0x1402, 0x1403 };
STATIC volatile UINT32  *mBhiSink;       // \BHISINK.TXT: the endpoint's MSI is pointed at a DRAM page instead of GITS_TRANSLATER, to see whether the chip raises an MSI at all (and with which data)

STATIC VOID
BhiPrepare (VOID)
{
  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *Fs = NULL;
  EFI_FILE_PROTOCOL               *Root = NULL, *File = NULL;
  EFI_PHYSICAL_ADDRESS            Addr = 0xFFFFFFFFULL;
  UINT32                          Ptr, Hops, Cw, MsiAddr = 0x17150040;
  CONST UINT64                    Cfg = 0x60100000ULL;       // EP config space (type 0, bus 1 dev 0)

  if (SelfFileExists (L"\\BHISINK.TXT")) {
    EFI_PHYSICAL_ADDRESS  Sink = 0xFFFFFFFFULL;
    if (!EFI_ERROR (gBS->AllocatePages (AllocateMaxAddress, EfiBootServicesData, 1, &Sink))) {
      SetMem ((VOID *)(UINTN)Sink, 0x1000, 0xFF);
      WriteBackInvalidateDataCacheRange ((VOID *)(UINTN)Sink, 0x1000);
      mBhiSink = (volatile UINT32 *)(UINTN)Sink;
      MsiAddr  = (UINT32)Sink;
      ItsLogF ("BHI: SINK mode: the MSI address is DRAM %x, not GITS_TRANSLATER\n", MsiAddr);
    }
  }

  // the chip's DMA reads and its MSI write come from SMMU stream 0x1401
  SmmuForgetSid (0x1401);
  ItsLogF ("BHI: SMMU stream 0x1401 %a\n", SmmuBypassSid (0x1401) ? "identity mapped" : "NOT mapped");

  // variants of how the doorbell write reaches GITS_TRANSLATER (the real MSI did not become an LPI with the plain identity mapping)
  {
    UINT32  Vn = 0, Sn = 0xFFFFFFFF, NumSm = MMR (SMMU_B + 0x20) & 0xFF, Ix;
    if (SelfFileExists (L"\\BHIVAR1.TXT")) {
      Vn = 1;
    } else if (SelfFileExists (L"\\BHIVAR2.TXT")) {
      Vn = 2;
    }
    for (Ix = 0; Ix < NumSm; Ix++) {
      UINT32  Smr = MMR (SMMU_B + 0x800 + 4ULL * Ix);
      if ((Smr & 0x80000000U) != 0 && (Smr & 0x7FFF) == 0x1401) {
        Sn = Ix;
        break;
      }
    }
    if (Vn == 1 && Sn != 0xFFFFFFFF) {
      MMW (SMMU_B + 0xC00 + 4ULL * Sn, 0x00020000U);                 // S2CR TYPE = bypass: the stream skips the SMMU translation altogether
      ItsLogF ("BHI: VAR1: SMMU entry %u -> BYPASS (s2cr=%x)\n", Sn, MMR (SMMU_B + 0xC00 + 4ULL * Sn));
    } else if (Vn == 2 && Sn != 0xFFFFFFFF && mSmmuPgd != NULL) {
      // VAR2: like Android's iommu-dma MSI page: IOVA 0xA0000040 -> PA 0x17150040 as a device/MMIO page.  Block 2 (0x80000000-0xBFFFFFFF) becomes a level-2 table of 2 MB blocks (identity, normal) except IOVA 0xA0000000 -> PA 0x17000000 (Device).
      UINT32                Cb  = MMR (SMMU_B + 0xC00 + 4ULL * Sn) & 0xFF;
      UINT64                CbB = SMMU_CB_B + 0x1000ULL * Cb;
      EFI_PHYSICAL_ADDRESS  L2  = 0;
      UINT32                Jx;
      if (!EFI_ERROR (gBS->AllocatePages (AllocateAnyPages, EfiReservedMemoryType, 1, &L2))) {
        UINT64  *Tb = (UINT64 *)(UINTN)L2;
        for (Jx = 0; Jx < 512; Jx++) {
          Tb[Jx] = (0x80000000ULL + ((UINT64)Jx << 21)) | (1ULL << 10) | (3ULL << 8) | (1ULL << 6) | 1ULL;
        }
        Tb[256] = 0x17000000ULL | (1ULL << 10) | (3ULL << 8) | (1ULL << 6) | (1ULL << 2) | 1ULL;
        GeniCacheOp (Tb, 4096);
        mSmmuPgd[2] = (UINT64)L2 | 3ULL;
        GeniCacheOp (mSmmuPgd, 4 * sizeof (UINT64));
        MMW (CbB + 0x618, 0);                                        // TLBIALL
        MMW (CbB + 0x7F0, 0);                                        // TLBSYNC
        MsiAddr = 0xA0150040;
        ItsLogF ("BHI: VAR2: IOVA 0xA0000000 -> PA 0x17000000 (device) via L2 table %lx; MSI address will be %x\n", (UINT64)L2, MsiAddr);
      }
    }
  }

  // MSI capability of the endpoint: 16 vectors, address = GITS_TRANSLATER, data base 0 (vector n -> EventID n)
  Ptr = MMR (Cfg + 0x34) & 0xFF;
  for (Hops = 0; Ptr >= 0x40 && Ptr < 0x100 && Hops < 32; Hops++) {
    Cw = MMR (Cfg + Ptr);
    if ((Cw & 0xFF) == 0x05) {
      UINT32   Ctl   = Cw >> 16;
      BOOLEAN  Is64  = ((Ctl & 0x80) != 0) ? TRUE : FALSE;
      ItsLogF ("BHI: MSI capability at 0x%x control=0x%x 64bit=%u mask=%u MMC=%u\n", Ptr, Ctl, Is64, (Ctl >> 8) & 1, (Ctl >> 1) & 7);
      MMW (Cfg + Ptr + 4, MsiAddr);
      MMW (Cfg + Ptr + 8, 0);
      if (Is64) {
        MMW (Cfg + Ptr + 0xC, 0);
      }
      Ctl = (Ctl & ~0x70U) | (4U << 4) | 1U;                 // MME = 4 (16 vectors), enable
      MMW (Cfg + Ptr, (Cw & 0xFFFF) | (Ctl << 16));
      ItsLogF ("BHI: MSI now control=0x%x addr=0x%x data=0x%x\n", MMR (Cfg + Ptr) >> 16, MMR (Cfg + Ptr + 4), MMR (Cfg + Ptr + (Is64 ? 0xC : 8)));
      break;
    }
    Ptr = (Cw >> 8) & 0xFF;
  }

  // the SBL image, in DRAM below 4 GB (the identity context covers 0-4 GB)
  if (mSelfVolume != NULL &&
      !EFI_ERROR (gBS->HandleProtocol (mSelfVolume, &gEfiSimpleFileSystemProtocolGuid, (VOID **)&Fs)) &&
      !EFI_ERROR (Fs->OpenVolume (Fs, &Root))) {
    if (!EFI_ERROR (Root->Open (Root, &File, L"\\SBL.BIN", EFI_FILE_MODE_READ, 0))) {
      UINTN  Size = 0x40000;
      if (!EFI_ERROR (gBS->AllocatePages (AllocateMaxAddress, EfiBootServicesData, EFI_SIZE_TO_PAGES (Size), &Addr))) {
        mBhiImg = (UINT8 *)(UINTN)Addr;
        ZeroMem (mBhiImg, Size);
        if (!EFI_ERROR (File->Read (File, &Size, mBhiImg))) {
          mBhiImgSize = Size;
        }
      }
      File->Close (File);
    }
    Root->Close (Root);
  }
  ItsLogF ("BHI: SBL image at %lx size 0x%lx first dword %x\n", (UINT64)(UINTN)mBhiImg, (UINT64)mBhiImgSize, (mBhiImg != NULL) ? *(UINT32 *)mBhiImg : 0);
}

STATIC VOID
BhiRun (IN UINT64 Lpi)
{
  CONST UINT64  Bar0 = 0x60200000ULL;
  UINT64        Bhi, Img = (UINT64)(UINTN)mBhiImg, Iar, Seen[6];
  UINT32        Bhioff, I, K, NSeen = 0, Total = 0, S0, S1, E1, SinkLogged = 0, SinkHits = 0;
  EFI_TPL       OldTpl;

  Bhioff = MMR (Bar0 + 0x28);
  ItsLogF ("BHI: MHIVER=%x MHICFG=%x MHICTRL=%x MHISTATUS=%x BHIOFF=%x\n", MMR (Bar0 + 0x08), MMR (Bar0 + 0x10), MMR (Bar0 + 0x38), MMR (Bar0 + 0x48), Bhioff);
  if (mBhiImg == NULL || mBhiImgSize == 0 || Bhioff == 0 || Bhioff > 0x1000) {
    ItsLogF ("BHI: cannot run (image or BHIOFF missing)\n");
    return;
  }
  Bhi = Bar0 + Bhioff;
  ItsLogF ("BHI: before: BHIVER=%x/%x EXECENV=%x STATUS=%x ERRCODE=%x\n", MMR (Bhi), MMR (Bhi + 4), MMR (Bhi + 0x28), MMR (Bhi + 0x2C), MMR (Bhi + 0x30));
  WriteBackInvalidateDataCacheRange (mBhiImg, mBhiImgSize);

  OldTpl = gBS->RaiseTPL (TPL_HIGH_LEVEL);
  ItsWritePmr (0xFF);
  for (I = 0; I < 16; I++) {                                 // drain whatever is pending
    Iar = ItsReadIar1 () & 0xFFFFFF;
    if (Iar >= 1020) {
      break;
    }
    ItsWriteEoir1 (Iar);
  }
  MMW (Bhi + 0x2C, 0);                                       // BHI_STATUS
  MMW (Bhi + 0x0C, (UINT32)(Img >> 32));                     // BHI_IMGADDR_HIGH
  MMW (Bhi + 0x08, (UINT32)Img);                             // BHI_IMGADDR_LOW
  MMW (Bhi + 0x10, (UINT32)mBhiImgSize);                     // BHI_IMGSIZE
  MMW (Bhi + 0x20, 0);                                       // BHI_INTVEC: MSI vector 0
  MMW (Bhi + 0x18, 0x12345678U & 0x3FFFFFFFU);               // BHI_IMGTXDB: session id -> go
  S0 = MMR (Bhi + 0x2C);
  for (I = 0; I < 60000; I++) {                              // 3 s in 50 us steps
    Iar = ItsReadIar1 () & 0xFFFFFF;
    if (Iar < 1020) {
      Total++;
      for (K = 0; K < NSeen && Seen[K] != Iar; K++) {
      }
      if (K == NSeen && NSeen < 6) {
        Seen[NSeen++] = Iar;
        ItsLogF ("BHI: t=%u us: acknowledged INTID %lx%a\n", I * 50, Iar, (Iar == Lpi) ? "   <== the chip's MSI vector 0 as an LPI" : "");
        if (Iar >= 0x2020 && Iar < 0x2020 + BHI_NCAND) {
          ItsLogF ("BHI:   -> the chip's MSI arrived with DeviceID 0x%x\n", mBhiCand[Iar - 0x2020]);
        }
      }
      ItsWriteEoir1 (Iar);
    }
    if (mBhiSink != NULL && (I % 20) == 0) {
      InvalidateDataCacheRange ((VOID *)mBhiSink, 64);
      for (K = 0; K < 16; K++) {
        if (mBhiSink[K] != 0xFFFFFFFFU && SinkLogged < 8) {
          ItsLogF ("BHI: t=%u us: SINK[%u] = %x  <== the chip wrote an MSI to DRAM\n", I * 50, K, mBhiSink[K]);
          mBhiSink[K] = 0xFFFFFFFFU;
          WriteBackInvalidateDataCacheRange ((VOID *)mBhiSink, 64);
          SinkLogged++;
          SinkHits++;
        }
      }
    }
    if ((I % 400) == 0) {
      S1 = MMR (Bhi + 0x2C);
      E1 = MMR (Bhi + 0x28);
      if (S1 != S0 || I == 0) {
        ItsLogF ("BHI: t=%u us: STATUS=%x EXECENV=%x ERRCODE=%x\n", I * 50, S1, E1, MMR (Bhi + 0x30));
        S0 = S1;
      }
    }
    gBS->Stall (50);
  }
  gBS->RestoreTPL (OldTpl);
  ItsLogF ("BHI: after 3 s: STATUS=%x EXECENV=%x ERRCODE=%x MHISTATUS=%x; %u interrupts acknowledged, %u distinct\n", MMR (Bhi + 0x2C), MMR (Bhi + 0x28), MMR (Bhi + 0x30), MMR (Bar0 + 0x48), Total, NSeen);
  {
    // where did the chip's MSI write go?  SMMU faults (global and the context bank of stream 0x1401) and the root complex's own MSI receiver (DWC MSI_CTRL: a write to its address is captured there, not forwarded)
    UINT32  NumCb = MMR (0x15000024ULL) & 0xFF, NumSmrg = MMR (0x15000020ULL) & 0xFF;
    ItsLogF ("BHI: SMMU sGFSR=%x sGFAR=%lx sGFSYNR0..2=%x %x %x  RC MSI ctrl: addr=%x:%x en=%x mask=%x status=%x\n", MMR (0x15000048ULL), M64R (0x15000040ULL),
             MMR (0x15000050ULL), MMR (0x15000054ULL), MMR (0x15000058ULL), MMR (DBI_B + 0x824), MMR (DBI_B + 0x820), MMR (DBI_B + 0x828), MMR (DBI_B + 0x82C), MMR (DBI_B + 0x830));
    for (I = 0; I < NumSmrg && I < 256; I++) {
      UINT32  Smr = MMR (0x15000800ULL + 4ULL * I);
      if ((Smr & 0x80000000U) != 0 && (Smr & 0x7FFF) == 0x1401) {
        UINT32  S2 = MMR (0x15000C00ULL + 4ULL * I), Cb = S2 & 0xFF;
        ItsLogF ("BHI: SMMU smr[%u]=%x s2cr=%x -> CB%u FSR=%x FAR=%lx FSYNR0=%x\n", I, Smr, S2, Cb, MMR (0x15080000ULL + 0x1000ULL * Cb + 0x58),
                 M64R (0x15080000ULL + 0x1000ULL * Cb + 0x60), MMR (0x15080000ULL + 0x1000ULL * Cb + 0x68));
      }
    }
    for (I = 0; I < NumCb && I < 128; I++) {
      UINT32  F = MMR (0x15080000ULL + 0x1000ULL * I + 0x58);
      if (F != 0) {
        ItsLogF ("BHI: SMMU CB%u FSR=%x FAR=%lx FSYNR0=%x\n", I, F, M64R (0x15080000ULL + 0x1000ULL * I + 0x60), MMR (0x15080000ULL + 0x1000ULL * I + 0x68));
      }
    }
  }
  if (mBhiSink != NULL) {
    ItsLogF ("BHI: SINK writes seen: %u\n", SinkHits);
  }
}

STATIC VOID
ItsTestBody (VOID)
{
  UINT64  Mp, Aff, PeBase = 0, Typer;
  UINT32  Pn = 0, I;
  UINT8   *Cfg, *Pend, *DevTbl, *ColTbl, *Itt, *DevL2, *DevL2b, *IttRp;
  UINT64  Attr = (1ULL << 10) | (7ULL << 7);     // GICR_*BASER: inner shareable, inner WB RaWa
  UINT64  BAttr = (7ULL << 59) | (1ULL << 10);   // GITS_BASER / CBASER: inner WB, inner shareable
  CONST UINT32 Dev = 0x1401, Ev = 0, Lpi = 0x2010;      // WINSEQ: the endpoint exactly like Windows (root port dev 0x1301 below)
  UINT64  Iar;
  EFI_TPL OldTpl;

  if (mBhiMode) {
    BhiPrepare ();
  }
  Mp  = ItsReadMpidr ();
  Aff = ((Mp >> 32) & 0xFF) << 24 | (Mp & 0xFFFFFF);
  ItsLogF ("ITSTEST: MPIDR=%lx aff=%lx SRE=%lx IGRPEN1=%lx PMR=%lx\n", Mp, Aff, ItsReadSre (), ItsReadIgrpen1 (), ItsReadPmr ());
  ItsRegDump ("initial");
  ItsLogF ("ITSTEST: CurrentEL=%lx ICC_CTLR=%lx BPR1=%lx RPR=%lx\n", ItsReadEl (), ItsReadIcCtlr (), ItsReadBpr1 (), ItsReadRpr ());
  for (I = 0; I < 8; I++) {
    UINT64 R = GICR_BASE + I * GICR_STRIDE;
    Typer = M64R (R + 8);
    ItsLogF ("ITSTEST: GICR%u TYPER=%lx WAKER=%x CTLR=%x\n", I, Typer, MMR (R + 0x14), MMR (R));
    if ((Typer >> 32) == Aff) {
      PeBase = R;
      Pn = (UINT32)((Typer >> 8) & 0xFFFF);
    }
  }
  if (PeBase == 0) {
    ItsLogF ("ITSTEST: no redistributor matches this PE\n");
    return;
  }
  ItsLogF ("ITSTEST: this PE = redistributor @%lx processor number %u; GICD CTLR=%x TYPER=%x; ITS CTLR=%x IIDR=%x CBASER=%lx BASER0=%lx BASER1=%lx\n",
          PeBase, Pn, MMR (0x17100000), MMR (0x17100004), MMR (ITS_BASE), MMR (ITS_BASE + 4), M64R (ITS_BASE + 0x80), M64R (ITS_BASE + 0x100), M64R (ITS_BASE + 0x108));
  if ((MMR (PeBase) & 1) != 0) {
    ItsLogF ("ITSTEST: LPIs are already enabled on this redistributor (%x) - cannot set up new tables, stopping\n", MMR (PeBase));
    return;
  }

  Cfg    = ItsAllocAt (0x81FB0000ULL, 0x6000);       // WINADDR: the physical places Windows used
  if (Cfg == NULL) { Cfg = ItsAlloc (0x6000, 0x1000); }      // LPI configuration table: IDbits 13 -> INTIDs 8192..16383 -> 8 KB
  Pend   = ItsAllocAt (0x81FC0000ULL, 0x10000);
  if (Pend == NULL) { Pend = ItsAlloc (0x10000, 0x10000); }    // pending table (64 KB aligned, zeroed)
  DevTbl = ItsAllocAt (0x8321C000ULL, 0x100000);
  if (DevTbl == NULL) { DevTbl = ItsAlloc (0x1000, 0x1000); }
  ColTbl = (Pend == (UINT8 *)(UINTN)0x81FC0000ULL) ? (Pend + 0x1000) : ItsAlloc (0x1000, 0x1000);       // Windows: collection table inside the first 64 KB of the pending table region
  mItsQ  = ItsAllocAt (0x82A90000ULL, 0x1000);
  if (mItsQ == NULL) { mItsQ = ItsAlloc (0x1000, 0x10000); }       // this ITS drops CBASER address bits 15:12: the queue must sit on a 64 KB boundary (Windows: 0x82A90000)
  Itt    = ItsAllocAt (0xAFFEB9000ULL, 0x1000);      // HIGHMEM: where Windows put them
  if (Itt == NULL) { Itt = ItsAlloc (0x1000, 0x100); }
  DevL2b = ItsAllocAt (0xAFFEBD000ULL, 0x1000);
  if (DevL2b == NULL) { DevL2b = ItsAlloc (0x1000, 0x1000); }
  IttRp  = ItsAllocAt (0xAFFEBC000ULL, 0x1000);
  if (IttRp == NULL) { IttRp = ItsAlloc (0x1000, 0x100); }
  DevL2  = ItsAllocAt (0xAFFEBA000ULL, 0x1000);
  if (DevL2 == NULL) { DevL2 = ItsAlloc (0x1000, 0x1000); }       // level-2 page of the two-level device table
  if (Cfg == NULL || Pend == NULL || DevTbl == NULL || ColTbl == NULL || mItsQ == NULL || Itt == NULL || DevL2 == NULL || DevL2b == NULL || IttRp == NULL) {
    ItsLogF ("ITSTEST: allocation failed\n");
    return;
  }
  Cfg[0] = 0x71;
  {
    UINT32 Q;
    for (Q = 0; Q < 16; Q++) {
      Cfg[0x10 + Q] = 0x41;
    }
    if (mBhiMode) {
      for (Q = 0; Q < 16; Q++) {
        Cfg[0x20 + Q] = 0x41;         // LPIs 0x2020.. for the DeviceID hunt
      }
    }
  }                  // priority 0xA0, enabled
  WriteBackInvalidateDataCacheRange (Cfg, 0x6000);
  WriteBackInvalidateDataCacheRange (Pend, 0x10000);
  ItsLogF ("ITSTEST: itt=%p ittrp=%p devl2=%p devl2b=%p\n", Itt, IttRp, DevL2, DevL2b);
  ItsLogF ("ITSTEST: tables cfg=%p pend=%p dev=%p col=%p queue=%p itt=%p\n", Cfg, Pend, DevTbl, ColTbl, mItsQ, Itt);

  // redistributor: LPI tables, then EnableLPIs
  M64W (PeBase + 0x70, ((UINT64)(UINTN)Cfg) | Attr | 14);       // variant: IDbits 14 like Windows (GICD_TYPER.IDbits says 13)
  M64W (PeBase + 0x78, ((UINT64)(UINTN)Pend) | Attr);      // PTZ: the pending table is zero
  MMW (PeBase, MMR (PeBase) | 1);
  for (I = 0; I < 1000 && (MMR (PeBase) & 0x8) != 0; I++) {
    gBS->Stall (10);
  }
  ItsLogF ("ITSTEST: GICR PROPBASER=%lx PENDBASER=%lx CTLR=%x\n", M64R (PeBase + 0x70), M64R (PeBase + 0x78), MMR (PeBase));
  // ALLGICR: Windows enables LPIs on all 8 redistributors (same property table, one pending table each).  Do the same for the ones that are awake (WAKER.ProcessorSleep = 0).
  {
    UINT32 Rn;
    for (Rn = 1; Rn < 8; Rn++) {
      UINT64 Rb = GICR_BASE + Rn * GICR_STRIDE;
      UINT8  *Pn2;
      if ((MMR (Rb + 0x14) & 6) != 0) {
        ItsLogF ("ITSTEST: GICR%u is asleep (WAKER=%x), skipped\n", Rn, MMR (Rb + 0x14));
        continue;
      }
      Pn2 = ItsAlloc (0x10000, 0x10000);
      if (Pn2 == NULL) {
        continue;
      }
      WriteBackInvalidateDataCacheRange (Pn2, 0x10000);
      M64W (Rb + 0x70, ((UINT64)(UINTN)Cfg) | Attr | 14);
      M64W (Rb + 0x78, ((UINT64)(UINTN)Pn2) | Attr);
      MMW (Rb, MMR (Rb) | 1);
      ItsLogF ("ITSTEST: GICR%u LPIs on: PROPBASER=%lx PENDBASER=%lx CTLR=%x\n", Rn, M64R (Rb + 0x70), M64R (Rb + 0x78), MMR (Rb));
    }
  }

  // ITS: disable, set tables + command queue, enable
  MMW (ITS_BASE, MMR (ITS_BASE) & ~1U);
  for (I = 0; I < 1000 && (MMR (ITS_BASE) & 0x80000000U) == 0; I++) {
    gBS->Stall (10);
  }
  ((UINT64 *)DevTbl)[10] = (1ULL << 63) | (UINT64)(UINTN)DevL2;      // 0x1401 >> 9
  if (mBhiMode) {
    UINT32  Kc;
    for (Kc = 0; Kc < BHI_NCAND; Kc++) {
      UINT32  Idx = mBhiCand[Kc] >> 9;
      if ((((UINT64 *)DevTbl)[Idx] & (1ULL << 63)) == 0 && Idx != 9 && Idx != 10) {
        VOID  *P = ItsAlloc (0x1000, 0x1000);
        if (P != NULL) {
          ((UINT64 *)DevTbl)[Idx] = (1ULL << 63) | (UINT64)(UINTN)P;       // level-2 page for the candidate DeviceIDs
        }
      }
    }
  }
  ((UINT64 *)DevTbl)[9] = (1ULL << 63) | (UINT64)(UINTN)DevL2b;      // 0x1301 >> 9                                     // L1[0] = valid | level-2 page (DeviceIDs 0..511)
  WriteBackInvalidateDataCacheRange (DevTbl, 0x1000);
  M64W (ITS_BASE + 0x100, (1ULL << 63) | (1ULL << 62) | BAttr | ((UINT64)(UINTN)DevTbl) | 0xFE);        // 255 pages like Windows        // device table: flat, 4 KB page, 1 page
  M64W (ITS_BASE + 0x108, (1ULL << 63) | BAttr | ((UINT64)(UINTN)ColTbl));        // collection table
  M64W (ITS_BASE + 0x80, (1ULL << 63) | BAttr | ((UINT64)(UINTN)mItsQ));          // command queue, 1 page
  M64W (ITS_BASE + 0x88, 0);
  ItsLogF ("ITSTEST: ITS BASER0=%lx BASER1=%lx CBASER=%lx\n", M64R (ITS_BASE + 0x100), M64R (ITS_BASE + 0x108), M64R (ITS_BASE + 0x80));
  mItsQw = 0;
  MMW (ITS_BASE, MMR (ITS_BASE) | 1);
  ItsLogF ("ITSTEST: ITS CTLR=%x\n", MMR (ITS_BASE));

  {
    UINT32 N;
    // Windows' own stream (rp45 queue dump): MAPD(RP) MAPC MAPTI(RP) INV, MAPD(EP), 16 x MAPTI, 16 x INV - no SYNC, no INVALL
    // STALLTEST: Windows' very first command is MAPD with Size 9 (10 event id bits); this ITS only has 8, so the queue stalls; rpfix then rewrites Size to 7 and sets CWRITER.Retry
    ItsCmd (8 | (0x1301ULL << 32), 9, (1ULL << 63) | (UINT64)(UINTN)IttRp, 0);
    ItsKick ("STALLTEST MAPD size 9");
    if ((MMR (ITS_BASE + 0x90) & 1) != 0) {
      ((volatile UINT64 *)mItsQ)[1] = 7;
      WriteBackInvalidateDataCacheRange (mItsQ, 0x1000);
      M64W (ITS_BASE + 0x88, mItsQw | 1);
      gBS->Stall (50000);
      ItsLogF ("ITSTEST: after Retry: CWRITER=%x CREADR=%x\n", MMR (ITS_BASE + 0x88), MMR (ITS_BASE + 0x90));
    }
    ItsCmd (9, 0, (1ULL << 63) | ((UINT64)Pn << 16) | 0, 0);
    ItsCmd (0x0A | (0x1301ULL << 32), 0 | (0x2000ULL << 32), 0, 0);
    ItsCmd (0x0C | (0x1301ULL << 32), 0, 0, 0);
    ItsCmd (8 | ((UINT64)Dev << 32), 7, (1ULL << 63) | (UINT64)(UINTN)Itt, 0);
    for (N = 0; N < 16; N++) {
      ItsCmd (0x0A | ((UINT64)Dev << 32), N | ((UINT64)(Lpi + N) << 32), 0, 0);
    }
    for (N = 0; N < 16; N++) {
      ItsCmd (0x0C | ((UINT64)Dev << 32), N, 0, 0);
    }
  }
  if (mBhiMode) {
    UINT32  Kd;
    for (Kd = 0; Kd < BHI_NCAND; Kd++) {
      UINT8  *T = ItsAlloc (0x1000, 0x100);
      if (T == NULL) {
        break;
      }
      ItsCmd (8 | ((UINT64)mBhiCand[Kd] << 32), 7, (1ULL << 63) | (UINT64)(UINTN)T, 0);
      ItsCmd (0x0A | ((UINT64)mBhiCand[Kd] << 32), 0 | ((UINT64)(0x2020 + Kd) << 32), 0, 0);
      ItsCmd (0x0C | ((UINT64)mBhiCand[Kd] << 32), 0, 0, 0);
    }
    ItsLogF ("BHI: DeviceID hunt: %u candidate devices mapped (event 0 -> LPI 0x2020 + index)\n", (UINT32)BHI_NCAND);
  }
  ItsKick ("WINSEQ stream");
  if (!mBhiMode) {
    ItsRegDump ("setup");              // reads ITS+0x114, which can freeze the bus (seen once in a BHI run, 2026-10-31): not needed for the BHI test
  }
  ItsLogF ("ITSTEST: device table[%u]=%lx ITT[%u]=%x collection table[0..7]=%lx\n", Dev, ((UINT64 *)DevL2)[Dev & 0x1FF], Ev, ((UINT32 *)Itt)[Ev + 1], *(UINT64 *)ColTbl);

  if (mBhiMode) {
    BhiRun (Lpi);                                              // the chip raises the MSI (BHI download) instead of a software INT command
    MMW (ITS_BASE, MMR (ITS_BASE) & ~1U);
    ItsLogF ("ITSTEST: done (BHI mode)\n");
    return;
  }

  OldTpl = gBS->RaiseTPL (TPL_HIGH_LEVEL);                                                         // interrupts off: we poll the CPU interface by hand
  ItsWritePmr (0xFF);
  for (I = 0; I < 4; I++) {      // DELAYROUND: round 3 runs after a 30 s wait
    UINT32 N = 0;
    UINT32 T;
    if (I == 3) {
      gBS->RestoreTPL (OldTpl);
      gBS->Stall (30000000);
      OldTpl = gBS->RaiseTPL (TPL_HIGH_LEVEL);
      ItsLogF ("ITSTEST: waited 30 s\n");
    }
    ItsCmd (3 | ((UINT64)Dev << 32), Ev, 0, 0);                                                    // INT (round 0: nothing else)
    if (I == 2) {
      ItsCmd (0x0D, 0, 0, 0);
    }
    if (I >= 1) {
      ItsCmd (5, 0, ((UINT64)Pn << 16), 0);
    }
    ItsKick ("INT/SYNC");
    for (T = 0; T < 2000; T++) {
      Iar = ItsReadIar1 () & 0xFFFFFF;
      if (Iar != 1023) {
        ItsLogF ("ITSTEST: round %u: acknowledged INTID %lx%a\n", I, Iar, (Iar == Lpi) ? "   <== OUR LPI" : "");
        ItsWriteEoir1 (Iar);
        N++;
        if (N > 6) {
          break;
        }
      }
      gBS->Stall (5);
    }
    ItsLogF ("ITSTEST: round %u done, %u interrupts acknowledged; pending table dword for LPI 0x2000..: %x %x\n", I, N, ((UINT32 *)Pend)[0x400 / 4], ((UINT32 *)Pend)[0x404 / 4]);
  }
  gBS->RestoreTPL (OldTpl);
  MMW (ITS_BASE, MMR (ITS_BASE) & ~1U);     // leave the ITS disabled; the redistributor keeps EnableLPIs until the next reset
  ItsLogF ("ITSTEST: done\n");
}

STATIC VOID
ItsTest (VOID)
{
  ItsTestBody ();
  WriteTestFile (L"\\ITSRES.TXT", mItsLog);
}

EFI_STATUS EFIAPI
UefiMain (IN EFI_HANDLE ImageHandle, IN EFI_SYSTEM_TABLE *SystemTable)
{
  EFI_STATUS                Status;
  EFI_DEVICE_PATH_PROTOCOL  *BootPath = NULL;
  EFI_HANDLE                NewImage = NULL;
  UINTN                     ExitDataSize = 0;

  DEBUG ((DEBUG_ERROR, "[MUCHAIN] start\n"));
  Print (L"[MUCHAIN] start\n");

  gBS->SetWatchdogTimer (0, 0, 0, NULL);   // disable the UEFI watchdog (default timer would reset us after ~30 s)
  ArmWatchdog (WDT_MS);

  // ACPI breadcrumb area (see refs/acpi/instrument_dsdt.py): last 64 KB of the RAM console
  ZeroMem ((VOID *)(UINTN)0xD7FF0000ULL, 0x500);
  ZeroMem ((VOID *)(UINTN)0xD7FF2000ULL, 0xC10);   // UFS HC register snapshots (refs/acpi/instrument_ufs_regs.py)
  *(volatile UINT32 *)(UINTN)0xD7FF0400ULL = 0x4D43554DU;   // "MUCM"
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] ACPI breadcrumb area cleared\n"));

  Status = FindBootMgr (&BootPath, ImageHandle);
  if (EFI_ERROR (Status)) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] bootmgfw.efi not found: %r\n", Status));
    Print (L"[MUCHAIN] bootmgfw.efi not found\n");
    CpuDeadLoop ();
    return Status;
  }

  {
    CHAR16 *T = ConvertDevicePathToText (BootPath, FALSE, FALSE);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] boot path: %s\n", T != NULL ? T : L"?"));
    if (T != NULL) {
      FreePool (T);
    }
  }

  HookAllPartitions ();
  DumpDiskPaths ();
  ProbeWindowsPartition ();

  {
    EFI_LOADED_IMAGE_PROTOCOL *Self = NULL;
    EFI_EVENT                 Timer = NULL;
    if (!EFI_ERROR (gBS->HandleProtocol (ImageHandle, &gEfiLoadedImageProtocolGuid, (VOID **)&Self)) && Self != NULL) {
      mSelfVolume = Self->DeviceHandle;
    }
    // Booted from the slot-a launcher (Android: boot_windows.sh writes \ONCEMODE.TXT + \ONCE.TXT, then bootctl set-active a + reboot):
    // Windows starts only when \ONCE.TXT can be consumed.  Every further boot of slot a (ABL keeps retrying it while its retry count lasts) resets at once, so ABL ends up on slot b = Android.
    // Boot menu (NEXT.md 0bz): MENU.TXT = Mu is always in the boot path of slot a.  NEXT.TXT = "W": start Windows this once (and put "A" back), anything else: hand over to Android (boot_b) directly.
    // No file is deleted here (the FAT driver has lost neighbouring directory entries on deletes).  If the Android launch returns, reset: ABL then falls back to slot b.
    if (SelfFileExists (L"\\MENU.TXT")) {
      if (SelfFirstByte (L"\\NEXT.TXT") == (INTN)'W') {
        SelfWriteBytes (L"NEXT.TXT", "A", 1);
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] MENU: Windows requested, NEXT.TXT back to A\n"));
      } else {
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] MENU: Android\n"));
        AndroidLaunch (ImageHandle, TRUE);
        gRT->ResetSystem (EfiResetCold, EFI_SUCCESS, 0, NULL);
        CpuDeadLoop ();
      }
    }
    if (SelfFileExists (L"\\ONCEMODE.TXT")) {
      if (SelfDeleteFile (L"\\ONCE.TXT")) {
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] ONCEMODE: \\ONCE.TXT consumed, starting Windows\n"));
        if (SelfFileExists (L"\\ANDROID.TXT")) {       // boot-menu stage 1: launch Android (boot_b) from here; ANDJUMP.TXT = really jump, otherwise only load + patch + log
          BOOLEAN Jmp = SelfFileExists (L"\\ANDJUMP.TXT");
          mAndStub = SelfFileExists (L"\\ANDSTUB.TXT");   // read before the deletes below: the FAT driver can lose neighbouring entries
          SelfDeleteFile (L"\\ANDROID.TXT");
          SelfDeleteFile (L"\\ANDJUMP.TXT");
          AndroidLaunch (ImageHandle, Jmp);
          gRT->ResetSystem (EfiResetCold, EFI_SUCCESS, 0, NULL);
          CpuDeadLoop ();
        }
        if (SelfFileExists (L"\\FDTSCAN.TXT")) {       // stage-0 experiment: report what ABL handed over, do not start Windows, go back to ABL
          SelfDeleteFile (L"\\FDTSCAN.TXT");
          FdtScan ();
          gRT->ResetSystem (EfiResetCold, EFI_SUCCESS, 0, NULL);
          CpuDeadLoop ();
        }
      } else {
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] ONCEMODE: no \\ONCE.TXT, resetting to hand control back to ABL\n"));
        gRT->ResetSystem (EfiResetCold, EFI_SUCCESS, 0, NULL);
        CpuDeadLoop ();
      }
    }
    Status = gBS->CreateEvent (EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, SnapTimer, NULL, &Timer);
    if (!EFI_ERROR (Status)) {
      Status = gBS->SetTimer (Timer, TimerPeriodic, 10000000);  // 1 s
    }
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] snapshot timer: %r (volume=%p)\n", Status, mSelfVolume));
  }

  Status = gBS->LoadImage (FALSE, ImageHandle, BootPath, NULL, 0, &NewImage);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] LoadImage: %r\n", Status));
  if (EFI_ERROR (Status)) {
    CpuDeadLoop ();
    return Status;
  }

  mOrigExitBs = gBS->ExitBootServices;
  gBS->ExitBootServices = HookExitBs;
  gBS->Hdr.CRC32 = 0;
  gBS->CalculateCrc32 (gBS, gBS->Hdr.HeaderSize, &gBS->Hdr.CRC32);

  {
    EFI_LOADED_IMAGE_PROTOCOL *Bm = NULL;
    if (!EFI_ERROR (gBS->HandleProtocol (NewImage, &gEfiLoadedImageProtocolGuid, (VOID **)&Bm)) && Bm != NULL) {
      mBmBase = (UINT64)(UINTN)Bm->ImageBase;
      mBmSize = Bm->ImageSize;
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] bootmgfw image 0x%lx size 0x%lx\n", mBmBase, mBmSize));
    }
  }
  mNoBoot = !SelfFileExists (L"\\BOOTOK.TXT") || SelfFileExists (L"\\NOBOOT.TXT");
  mNoWp   = SelfFileExists (L"\\NOWP.TXT");
  mLongRun = SelfFileExists (L"\\LONGRUN.TXT");   // decided BEFORE UfsProbe (a write-protected logdump makes the volume unreadable)
  mWdtKeep = mLongRun && !SelfFileExists (L"\\NOKEEP.TXT");
  EpssCapApply (TRUE);                            // CPU clusters capped from here on (see EpssCapApply); NOCAP.TXT turns it off
  if (SelfFileExists (L"\\REFRESH.TXT")) {
    StartRefresher ();
  }
  if (SelfFileExists (L"\\START0.TXT")) {
    StartProbe0 ();
  }
  if (SelfFileExists (L"\\DISP.TXT")) {
    LateDisplay ();
  }
  DumpProtocolsOnDisks ();
  UfsProbe ();
  TsensProbe ();
  SpmiProbe ();
  if (!mNoBoot && SelfFileExists (L"\\TOUCH.TXT")) {
    TouchProbe (TRUE);   // before the ADSP boot: the ADSP/PIL setup uses up the free SMMU stream-match entries / context banks
  }
  if (SelfFileExists (L"\\ADSP.TXT")) {
    PartFixModem ();
    PartProbe ();
    AdspLoad ();
    PartRestore ();
  }
  if (SelfFileExists (L"\\WINDELAY.TXT")) {
    // Windows' USB role switch (URS) picks host/device once, at start, from what is on the port.  Give the person time to swap the PC cable for an OTG device
    // (the ADSP is up and drives VBUS by itself), keeping the watchdog fed, before Windows starts.
    EFI_EVENT  PetEv = NULL;
    UINT32     Wi;
    if (!EFI_ERROR (gBS->CreateEvent (EVT_TIMER | EVT_NOTIFY_SIGNAL, TPL_CALLBACK, WdtPetCb, NULL, &PetEv))) {
      gBS->SetTimer (PetEv, TimerPeriodic, 10000000);
    }
    if (mMgD != NULL && SelfFileExists (L"\\UCSIINIT.TXT")) {
      RtrHostPrepare ();
      Wi = 180;
    } else {
      Wi = 0;
    }
    for (; Wi < 180; Wi++) {
      if (Wi % 30 == 0) {
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] WINDELAY: %u s of 180 s\n", Wi));
      }
      gBS->Stall (1000000);
    }
    if (PetEv != NULL) {
      gBS->SetTimer (PetEv, TimerCancel, 0);
    }
  }
  if (SelfFileExists (L"\\USBPREP.TXT")) {
    UsbPhyPrep ();
  }
  if (SelfFileExists (L"\\USBFN.TXT")) {
    UsbVbusOverride ();
    if (mNoBoot) {
      UsbRunTest ();
    }
  }
  if (SelfFileExists (L"\\PANEL.TXT")) {
    PanelMain ();
    if (mNoBoot) {
      DEBUG ((DEBUG_ERROR, "[MUCHAIN] PANEL.TXT: panel probe done\n"));
      CpuDeadLoop ();
      return EFI_SUCCESS;
    }
  }
  if (mNoBoot && SelfFileExists (L"\\TOUCH.TXT")) {
    TouchProbe (FALSE);
    TouchPowerDown ();
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] TOUCH.TXT: touch probe done\n"));
    CpuDeadLoop ();
    return EFI_SUCCESS;
  }
  if (mNoBoot && SelfFileExists (L"\\USBREPLAY.TXT")) {
    UsbReplay ();
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] USBREPLAY.TXT: replay done\n"));
    CpuDeadLoop ();
    return EFI_SUCCESS;
  }
  if (mNoBoot && SelfFileExists (L"\\USBPWR.TXT")) {
    UsbPwrProbe ();
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] USBPWR.TXT: usb power probe done\n"));
    CpuDeadLoop ();
    return EFI_SUCCESS;
  }
  if (mNoBoot && SelfFileExists (L"\\ITSTEST.TXT")) {
    ItsTest ();
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] ITSTEST.TXT: its/lpi test done\n"));
    CpuDeadLoop ();
    return EFI_SUCCESS;
  }
  if (mNoBoot && SelfFileExists (L"\\USBDEV.TXT")) {
    UsbDevProbe ();
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] USBDEV.TXT: usb device probe done\n"));
    CpuDeadLoop ();
    return EFI_SUCCESS;
  }
  mBhiMode = (mNoBoot && SelfFileExists (L"\\BHITEST.TXT")) ? TRUE : FALSE;
  if (mNoBoot) {
    // RPMh TCS writes only in the diagnostics-only mode: in a Windows run they left TCS0 in a state that stalled Mu's own RpmhDxe user (USB init, 2026-10-15)
    DispProbe ();
    CmdDbProbe ();
    RpmhProbe ();
    UsbGlueProbe ();
    PcieProbe ();
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] NOBOOT.TXT present: diagnostics only, NOT starting bootmgfw\n"));
    CpuDeadLoop ();
    return EFI_SUCCESS;
  }
  if (SelfFileExists (L"\\PCIE.TXT")) {
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] PCIE.TXT: bringing up PCIe0 / WCN7850 and leaving the link up for Windows\n"));
    CmdDbProbe ();
    mPcKeep = TRUE;
    PcieProbe ();
  }
  DumpConfigTables ();
  PatchBreakpoints (NewImage);
  StartProfiler ();
  InstallTraces ();

  DEBUG ((DEBUG_ERROR, "[MUCHAIN] StartImage(bootmgfw.efi)...\n"));
  Print (L"[MUCHAIN] starting bootmgfw.efi\n");
  Status = gBS->StartImage (NewImage, &ExitDataSize, NULL);
  DEBUG ((DEBUG_ERROR, "[MUCHAIN] StartImage returned: %r\n", Status));
  DumpHookStats ("after-return");

  // Returned (boot manager failed/exited): leave watchdog to reset us.
  CpuDeadLoop ();
  return Status;
}
