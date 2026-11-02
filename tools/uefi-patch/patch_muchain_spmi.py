"""MuChain: SpmiProbe() - READ-ONLY access to the PMIC arbiter (SPMI v7), as described by Linux spmi-pmic-arb.c.
  core   0xC400000 : +0x00 version, +0x2000+4*apid : apid map (ppid = bits[19:8], bit24 = irq owner)
  cnfg   0xC42D000 : +4*apid : owner EE (bits[2:0])
  obsrvr 0xC440000 : read channel of apid for EE0: +0x20*apid  (CMD +0x00, STATUS +0x08, RDATA0 +0x18, RDATA1 +0x1C)
Command word: (opc<<27) | ((reg&0xFF)<<4) | (len-1); EXT_READL opc = 1.
Prints: arbiter version, how many apids EE0 owns, a few PMIC peripheral IDs, and the PMK8550 RTC (sid 0, 0x6100) as epoch seconds."""
from pathlib import Path

c = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = c.read_text(encoding="utf-8")
assert "SpmiProbe" not in t
fn = r'''
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
'''
t = t.replace("\nSTATIC VOID\nDumpMemMap (VOID)", fn + "\nSTATIC VOID\nDumpMemMap (VOID)", 1)
old = "  TsensProbe ();\n"
assert old in t
t = t.replace(old, old + "  SpmiProbe ();\n", 1)
c.write_text(t, encoding="utf-8")
print("ok")
