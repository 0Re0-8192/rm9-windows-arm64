"""add_glnk.py : add BattGlinkHandoff() to MuChain.c (hand the mini glink state over to Windows, see NEXT.md 0k)."""
p = r"<RM9_WORKDIR>\refs\MuChain.c"
s = open(p, encoding="utf-8", newline="").read()
NL = chr(10)
BS = chr(92)
assert "BattGlinkHandoff" not in s

anchor = '  PL ("BATT: snapshot done, %u of %u values at 0x%lx' + BS + 'n", N, (UINT32)ARRAY_SIZE (Q), (UINT64)BATT_MAGIC_ADDR);' + NL + "}"
assert s.count(anchor) == 1, s.count(anchor)
s = s.replace(anchor, anchor[:-2] + NL + "  BattGlinkHandoff ();" + NL + "}", 1)

marker = "STATIC VOID" + NL + "BattSnapshot (VOID)"
assert s.count(marker) == 1
handoff = r'''// Hand the mini glink over to Windows: after EBS the same SMEM FIFOs can be driven from a user-mode client through rm9io (refs/winpe/battlive.ps1).
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

'''
s = s.replace(marker, handoff + marker, 1)
open(p, "w", encoding="utf-8", newline="").write(s)
print("ok")
