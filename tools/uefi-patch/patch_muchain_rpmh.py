"""MuChain: RpmhProbe() - M1 of the Wi-Fi bring-up.  Sends ONE ACTIVE-set RPMh write (VRM enable=1 of ldob15 = the 1.8 V WLAN IO rail that other
consumers also use) through the apps RSC DRV2, following Linux rpmh-rsc.c (HW v3.0 offsets), and reports completion.
RSC DRV2 base 0x17A20000, tcs-offset 0xD00, TCS stride 672, cmd stride 24; ACTIVE TCS ids = 0,1 (tcs-config: ACTIVE 2, SLEEP 2, WAKE 3, FAST 1)."""
from pathlib import Path

c = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = c.read_text(encoding="utf-8")
assert "RpmhProbe" not in t
fn = r'''
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
  TcsSetTrigger (Id, FALSE);
  TCS_W32 (Id, V3_CMDEN, 0);
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
'''
t = t.replace("\nSTATIC VOID\nDumpMemMap (VOID)", fn + "\nSTATIC VOID\nDumpMemMap (VOID)", 1)
old = "  CmdDbProbe ();\n"
assert old in t
t = t.replace(old, old + "  RpmhProbe ();\n", 1)
c.write_text(t, encoding="utf-8")
print("ok")
