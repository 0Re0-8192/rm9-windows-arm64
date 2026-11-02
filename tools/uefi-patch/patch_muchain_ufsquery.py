"""MuChain: UfsQueryFlag() - issue a UFS Query Request UPIU (READ_FLAG / SET_FLAG) through a FREE slot (31) of the
firmware driver's transfer list; call sites below only use READ_FLAG (device state is not changed)."""
from pathlib import Path

c = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = c.read_text(encoding="utf-8")
assert "UfsQueryFlag" not in t

fn = r'''
//
// Query Request UPIU through UTRL slot 31 (the firmware driver only uses slot 0).
// Opcode: 5 = READ_FLAG, 6 = SET_FLAG.   Returns the flag value in *Val.
//
STATIC EFI_STATUS
UfsQueryFlag (IN UINT64 Base, IN UINT8 Opcode, IN UINT8 Idn, OUT UINT8 *Val, OUT UINT8 *RespCode)
{
  STATIC EFI_PHYSICAL_ADDRESS  Ucd = 0;
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
  if (Ucd == 0) {
    Ucd = 0xFFFFFFFFULL;
    S = gBS->AllocatePages (AllocateMaxAddress, EfiBootServicesData, 1, &Ucd);
    if (EFI_ERROR (S)) {
      Ucd = 0;
      return S;
    }
  }
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
  Trd[6] = 0x00080010;                            // response UPIU: offset 0x10 dwords, length 8 dwords
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
          Opcode, Idn, Trd[2] & 0xFF, U[0x40], U[0x41], U[0x42], U[0x43], U[0x46], U[0x40 + 23], Spin));
  *RespCode = U[0x46];
  *Val = U[0x40 + 23];
  return ((Trd[2] & 0xFF) == 0) ? EFI_SUCCESS : EFI_DEVICE_ERROR;
}
'''
t = t.replace("\nSTATIC VOID\nUfsProbeOne (", fn + "\nSTATIC VOID\nUfsProbeOne (", 1)

# call READ_FLAGs at the end of the register/UTRL dump (inside UfsProbeOne, regs branch)
anchor = '        DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSTRL dump done (list at 0x%lx)\\n", Utrl));\n      }\n'
assert anchor in t
calls = anchor + r'''      {
        UINT8 V, R;
        EFI_STATUS Q;
        // READ_FLAG only (no device state change): fDeviceInit(1), fPermanentWPEn(2), fPowerOnWPEn(3)
        Q = UfsQueryFlag (Base, 5, 1, &V, &R);
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSQ fDeviceInit    : %r flag=%u qresp=0x%x\n", Q, V, R));
        Q = UfsQueryFlag (Base, 5, 2, &V, &R);
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSQ fPermanentWPEn : %r flag=%u qresp=0x%x\n", Q, V, R));
        Q = UfsQueryFlag (Base, 5, 3, &V, &R);
        DEBUG ((DEBUG_ERROR, "[MUCHAIN] UFSQ fPowerOnWPEn   : %r flag=%u qresp=0x%x\n", Q, V, R));
      }
'''
t = t.replace(anchor, calls, 1)
c.write_text(t, encoding="utf-8")
print("ok")
