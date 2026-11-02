// ===== USBREPLAY.TXT + NOBOOT: replay of Android's USB device-mode bring-up (final cycle of the boot-time MMIO trace, winboot/usbtrace2) from UEFI, without any Windows USB stack in between:
//   eUSB2 HS PHY init, QMP SS PHY init, dwc3 core soft reset / init / prtcap=device / event buffers, dwc3_msm QSCRATCH + glue writes, DCFG/DEVTEN, RUN.  Then the DWC3 state and the PC-side result are watched.
//   Success markers: GEVNTCOUNT0 > 0 / DSTS changes / a new (failing) USB device on the PC.
@@TABLES@@

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
