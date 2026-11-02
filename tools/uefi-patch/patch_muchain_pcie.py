"""MuChain: PcieProbe() - M2 of the Wi-Fi bring-up.  Brings PCIe0 (WCN7850 'kiwi', 17cb:1107) up from UEFI in NOBOOT mode:
RPMh rails -> TLMM (WLAN_EN, PERST) -> TCSR clkref -> GCC GDSC/clocks/BCR -> PARF (Linux qcom_pcie_init_2_7_0) -> PHY (DT qcom,phy-sequence)
-> PERST release -> LTSSM -> iATU CFG0 -> read endpoint ID.  Every step logs its read-back; every poll is bounded."""
from pathlib import Path

c = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
seq = Path(r"<RM9_WORKDIR>\refs\pcie_physeq.h").read_text(encoding="utf-8")
t = c.read_text(encoding="utf-8")
assert "PcieProbe" not in t
fn = seq + r'''

#define MMR(a)       (*(volatile UINT32 *)(UINTN)(a))
#define MMW(a, v)    (*(volatile UINT32 *)(UINTN)(a) = (UINT32)(v))
#define PL(...)      DEBUG ((DEBUG_ERROR, "[MUCHAIN] PCIE " __VA_ARGS__))
#define GCC_B        0x100000ULL
#define PARF_B       0x1C00000ULL
#define PHY_B        0x1C06000ULL
#define DBI_B        0x60000000ULL
#define ATU_B        0x60001000ULL
#define CFG_B        0x60100000ULL
#define TLMM_B       0x0F000000ULL
#define TCSR_CLKREF  0x01FF1100ULL      // tcsrcc base 0x1fc0000 + 0x31100 (mainline sm8650)

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
  S = gDS->AddMemorySpace (EfiGcdMemoryTypeMemoryMappedIo, Base, Len, EFI_MEMORY_UC);
  PL ("map %a 0x%lx+0x%lx: Add %r", Name, Base, Len, S);
  S = gDS->SetMemorySpaceAttributes (Base, Len, EFI_MEMORY_UC | EFI_MEMORY_XP);
  DEBUG ((DEBUG_ERROR, " SetAttr %r\n", S));
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

STATIC VOID
PcRail (IN CONST CHAR8 *Name, IN UINT32 Uv)
{
  UINT32 A = CmdDbAddr (Name);

  if (A == 0) {
    PL ("rail %a: not in cmd-db\n", Name);
    return;
  }
  PL ("rail %a addr=0x%x -> %u mV\n", Name, A, Uv / 1000);
  RpmhWrite (A + 0x0, Uv / 1000);
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

STATIC VOID
PcieProbe (VOID)
{
  UINT32  I, V;
  UINT32  N = (UINT32)(sizeof (mPciePhySeq) / sizeof (mPciePhySeq[0]));

  PL ("=== M2 start (phy seq %u entries)\n", N);
  PcEnsureMmio (GCC_B, 0x80000, "GCC");
  PcEnsureMmio (PARF_B, 0x8000, "PCIE0_WRAPPER");
  PcEnsureMmio (TLMM_B, 0x1000000, "TLMM");
  PcEnsureMmio (0x01F00000ULL, 0x100000, "TCSR");
  PcEnsureMmio (DBI_B, 0x200000, "PCIE0_AXI");
  PL ("pre: gcc gpll0=0x%08x pcie_0_gdsc=0x%08x phy_gdsc=0x%08x vote_en=0x%08x/0x%08x core_bcr=0x%x tcsr_clkref=0x%08x\n",
      MMR (GCC_B + 0x0), MMR (GCC_B + 0x6B004), MMR (GCC_B + 0x6C000), MMR (GCC_B + 0x52008), MMR (GCC_B + 0x52000),
      MMR (GCC_B + 0x6B000), MMR (TCSR_CLKREF));
  PL ("pre: tlmm gpio16=0x%x/0x%x gpio94=0x%x/0x%x gpio95=0x%x\n", MMR (TLMM_B + 0x10000), MMR (TLMM_B + 0x10004),
      MMR (TLMM_B + 0x5E000), MMR (TLMM_B + 0x5E004), MMR (TLMM_B + 0x5F000));

  // 1. PERST asserted (output low), clkreq to pcie0_clk_req_n, wake input
  PcGpio (94, 0x201, 0);
  PcGpio (95, (1 << 2) | 3, -1);
  PcGpio (96, 3, -1);

  // 2. rails: PCIe PHY supplies first, then the WCN7850 supplies, then WLAN_EN
  PcRail ("ldoe3", 912000);
  PcRail ("ldoi3", 1200000);
  PcRail ("ldoi1", 880000);
  PcRail ("smpc3", 916000);
  PcRail ("smpc2", 976000);
  PcRail ("smpi4", 940000);
  PcRail ("ldoc3", 1200000);
  PcRail ("ldob15", 1800000);
  PcRail ("smpc1", 1315000);
  PcRail ("smpc6", 1863000);
  PcDelayMs (5);
  PcGpio (16, (7 << 6) | 3 | (1 << 9), 1);               // WLAN_EN high, 16 mA, pull-up
  PL ("rails+WLAN_EN done\n");

  // 3. reference clock + GCC
  MMW (TCSR_CLKREF, MMR (TCSR_CLKREF) | 1);
  PL ("tcsr clkref=0x%08x\n", MMR (TCSR_CLKREF));
  MMW (GCC_B + 0x52150, 0);
  PcGdsc (0x6B004, 1U << 0, "pcie_0_gdsc");
  PcGdsc (0x6C000, 1U << 3, "pcie_0_phy_gdsc");
  PcRcgUpdate (0x6B074, 0, "aux(xo)");
  PcRcgUpdate (0x6B058, (6U << 8) | 5, "rchng(gpll0_even/3)");
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

  // 4. core + link-down BCR pulse (Linux: assert, 1 ms, deassert, 1 ms)
  MMW (GCC_B + 0x6B000, 1);
  MMW (GCC_B + 0x6C014, 1);
  PcDelayMs (2);
  MMW (GCC_B + 0x6B000, 0);
  MMW (GCC_B + 0x6C014, 0);
  PcDelayMs (2);

  // 5. PARF (qcom_pcie_init_2_7_0)
  PL ("parf sys_ctrl=0x%08x phy_ctrl=0x%08x pm_ctrl=0x%08x devtype=0x%x ltssm=0x%08x\n", MMR (PARF_B + 0x0), MMR (PARF_B + 0x40),
      MMR (PARF_B + 0x20), MMR (PARF_B + 0x1000), MMR (PARF_B + 0x1B0));
  MMW (PARF_B + 0x1000, 4);                                         // RC
  MMW (PARF_B + 0x40, MMR (PARF_B + 0x40) & ~1U);                   // PHY out of lowest power state
  MMW (PARF_B + 0x350, (UINT32)DBI_B);
  MMW (PARF_B + 0x354, 0);
  MMW (PARF_B + 0x634, (UINT32)ATU_B);
  MMW (PARF_B + 0x638, 0);
  MMW (PARF_B + 0x358, 0);
  MMW (PARF_B + 0x35C, 0x80000000);
  MMW (PARF_B + 0x0, MMR (PARF_B + 0x0) & ~(1U << 29));
  MMW (PARF_B + 0x174, MMR (PARF_B + 0x174) | (1U << 4));
  MMW (PARF_B + 0x20, MMR (PARF_B + 0x20) & ~(1U << 5));
  MMW (PARF_B + 0x1A8, MMR (PARF_B + 0x1A8) | (1U << 31));
  PL ("parf done: devtype=0x%x phy_ctrl=0x%08x dbi=0x%x/0x%x atu=0x%x\n", MMR (PARF_B + 0x1000), MMR (PARF_B + 0x40),
      MMR (PARF_B + 0x350), MMR (PARF_B + 0x354), MMR (PARF_B + 0x634));

  // 6. PHY: BCR pulse (NOCSR stays asserted while the tables are written), DT phy-sequence, pipe clock, release, wait for ready
  PL ("phy pre: status(0x214)=0x%x pwrdn(0x240)=0x%x\n", MMR (PHY_B + 0x214), MMR (PHY_B + 0x240));
  MMW (GCC_B + 0x6C01C, 1);
  MMW (GCC_B + 0x6C020, 1);
  PcDelayMs (2);
  MMW (GCC_B + 0x6C01C, 0);
  PcDelayMs (2);
  for (I = 0; I < N; I++) {
    MMW (PHY_B + mPciePhySeq[I][0], mPciePhySeq[I][1]);
    if (mPciePhySeq[I][2]) {
      gBS->Stall (mPciePhySeq[I][2]);
    }
  }
  PL ("phy seq written; pwrdn(0x240)=0x%x 0x244=0x%x\n", MMR (PHY_B + 0x240), MMR (PHY_B + 0x244));
  MMW (GCC_B + 0x6B070, 0);                                         // pipe mux -> PHY pipe clock
  MMW (GCC_B + 0x52008, MMR (GCC_B + 0x52008) | (1U << 4));         // pipe clk vote
  MMW (GCC_B + 0x6C020, 0);                                         // release NOCSR reset -> PHY starts
  V = PcPoll (PHY_B + 0x214, 1U << 6, 0, 200000);
  PL ("phy ready=%d status(0x214)=0x%x pipe mux=0x%x\n", V, MMR (PHY_B + 0x214), MMR (GCC_B + 0x6B070));

  // 7. PERST release (>=100 ms after power), link training
  PcDelayMs (100);
  MMW (TLMM_B + 0x1000ULL * 94 + 4, 2);
  PL ("PERST released, gpio94 io=0x%x\n", MMR (TLMM_B + 0x1000ULL * 94 + 4));
  MMW (PARF_B + 0x1B0, MMR (PARF_B + 0x1B0) | (1U << 8));
  for (I = 0; I < 15; I++) {
    PcDelayMs (100);
    V = MMR (DBI_B + 0x72C);
    PL ("t=%u ms: ltssm=0x%08x dbg1=0x%08x linkup=%d parf_status=0x%x\n", (I + 1) * 100, MMR (PARF_B + 0x1B0), V,
        (V & 0x10) && !(V & (1U << 29)), MMR (PARF_B + 0x230));
    if ((V & 0x10) && !(V & (1U << 29))) {
      break;
    }
  }

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
  PL ("EP cfg: id=0x%08x cmd/sts=0x%08x class=0x%08x hdr=0x%08x bar0=0x%08x  (expect id 0x110717cb)\n", MMR (CFG_B + 0), MMR (CFG_B + 4), MMR (CFG_B + 8),
      MMR (CFG_B + 0xC), MMR (CFG_B + 0x10));
  PL ("=== M2 end\n");
}
'''
t = t.replace("\nSTATIC VOID\nDumpMemMap (VOID)", fn + "\nSTATIC VOID\nDumpMemMap (VOID)", 1)
old = "  if (mNoBoot) {\n    DEBUG ((DEBUG_ERROR, \"[MUCHAIN] NOBOOT.TXT present: diagnostics only"
assert old in t
t = t.replace(old, "  if (mNoBoot) {\n    PcieProbe ();\n    DEBUG ((DEBUG_ERROR, \"[MUCHAIN] NOBOOT.TXT present: diagnostics only", 1)
c.write_text(t, encoding="utf-8")
print("ok")
