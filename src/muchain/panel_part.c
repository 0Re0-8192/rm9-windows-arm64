// ===== PANEL.TXT (+ PANEL60/90/120.TXT): switch the DSI command-mode panel's refresh rate with the panel's own timing-switch DCS sequences (from its device tree), sent through DSI0's command DMA.
// The bootloader (ABL) leaves the panel at 60 Hz; the TE pin (TLMM gpio86 = mdp_vsync) shows the real scan rate, which is measured before and after.
// DSI host (dsi.xml of the msm driver): CTRL 0x00, STATUS0 0x04 (bit1 DMA busy), CMD_DMA_CTRL 0x38 (bit26 LOW_POWER), DMA_BASE 0x44, DMA_LEN 0x48, TRIG_CTRL 0x80, TRIG_DMA 0x8c, INTR_CTRL 0x10c (bit0 DMA_DONE status, bit1 mask).
// DMA packet layout (dsi_cmd_dma_add): byte0 WC lo, byte1 WC hi, byte2 data type (|vc<<6), byte3 flags (0x80 last, 0x40 long packet), payload from byte4, padded with 0xFF to a multiple of 4.
#define DSI0_B       0x0AE94000ULL
#define DSI_REG(o)   (DSI0_B + 4ULL + (o))      // 6G host (msm dsi_cfg DSI_6G_REG_SHIFT): offset 0 is HW_VERSION (reads 0x20080000 = 2.8.0), dsi.xml offsets are +4 on the real block
#define TE_GPIO_IN   (0x0F100000ULL + 0x1000ULL * 86 + 4)
#define PANEL_FB     0xE3940000ULL
#define PANEL_BUF    (PANEL_FB + 1116ULL * 2480ULL * 4ULL - 8192ULL)    // last 8 KB of the visible framebuffer: mapped for the MDSS SMMU context; saved and restored around the transfer

@@SEQS@@

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
