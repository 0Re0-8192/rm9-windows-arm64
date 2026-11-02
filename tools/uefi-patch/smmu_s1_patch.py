p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
BS = chr(92)
NL = BS + 'n'

a = s.index('// Let stream id Sid bypass the Apps SMMU:')
b = s.index('STATIC VOID\nTouchProbe (VOID)')
code = r'''// UEFI leaves sCR0.USFCFG = 1 (unmatched stream = fault) and nothing for the QUP wrapper-1 DMA master (stream 0xa3), so its first DMA access is fatal; and this SMMU turns S2CR TYPE=bypass into fault,
// so give the stream a stage-1 translation context with an identity map of the low 4 GB (four 1 GB block descriptors, AArch32 long-descriptor format, 32-bit VA).
// arm-smmu v2: global SMR[n] @0x800+4n, S2CR[n] @0xC00+4n (CBNDX 7:0, TYPE 17:16), CBAR[n] @0x1000+4n, CBA2R[n] @0x1800+4n; context bank n at cb_base + n*0x1000 (cb_base = base + 0x80000 here):
// SCTLR 0x0, TTBCR2 0x10, TTBR0 0x20 (64 bit), TTBCR 0x30, MAIR0 0x38, TLBIALL 0x618, TLBSYNC 0x7F0, TLBSTATUS 0x7F4.
#define SMMU_CB_B  (SMMU_B + 0x80000ULL)

STATIC UINT64  mSmmuPgd[4] __attribute__ ((aligned (64)));

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
  PL ("SMMU: using smr/s2cr entry %u and context bank %u (of %u)%a", N, Cb, NumCb, "@@NL@@");
  if (N == 0xFFFFFFFF || Cb == 0xFFFFFFFF) {
    return FALSE;
  }
  CbB = SMMU_CB_B + 0x1000ULL * Cb;
  // identity map: 1 GB blocks, normal write-back, inner shareable, RW, access flag set
  for (I = 0; I < 4; I++) {
    mSmmuPgd[I] = ((UINT64)I << 30) | (1ULL << 10) | (3ULL << 8) | (1ULL << 6) | 1ULL;
  }
  GeniCacheOp (mSmmuPgd, sizeof (mSmmuPgd));
  MMW (SMMU_B + 0x1800 + 4ULL * Cb, 0);                                       // CBA2R: AArch32 format (VA64 = 0)
  MMW (SMMU_B + 0x1000 + 4ULL * Cb, 0x00010000);                              // CBAR: stage 1 translation, stage 2 bypass
  MMW (CbB + 0x30, 0x80003500U | (1U << 23));                                 // TTBCR: EAE, T0SZ 0, IRGN0=ORGN0=1 (WB), SH0=3, EPD1 (no TTBR1)
  MMW (CbB + 0x10, 0);                                                        // TTBCR2
  MMW (CbB + 0x20, (UINT32)(UINTN)mSmmuPgd);                                  // TTBR0 low
  MMW (CbB + 0x24, (UINT32)(((UINT64)(UINTN)mSmmuPgd) >> 32));                // TTBR0 high (ASID 0)
  MMW (CbB + 0x38, 0xFF);                                                     // MAIR0: attr 0 = normal WB
  MMW (CbB + 0x618, 0);                                                       // TLBIALL
  MMW (CbB + 0x7F0, 0);                                                       // TLBSYNC
  for (T = 0; T < 1000 && (MMR (CbB + 0x7F4) & 1U) != 0; T++) {
    gBS->Stall (10);
  }
  MMW (CbB + 0x0, 0x67);                                                      // SCTLR: M | TRE | AFE | CFRE | CFIE
  MMW (SMMU_B + 0xC00 + 4ULL * N, Cb);                                        // S2CR: TYPE 0 (translate), CBNDX = Cb
  MMW (SMMU_B + 0x800 + 4ULL * N, 0x80000000U | (Sid & 0x7FFF));              // SMR: valid, id = Sid
  R = MMR (SMMU_B + 0xC00 + 4ULL * N);
  PL ("SMMU: readback s2cr=0x%08x smr=0x%08x cbar=0x%08x cba2r=0x%08x sctlr=0x%08x ttbcr=0x%08x ttbr0=0x%08x_%08x mair0=0x%08x%a", R, MMR (SMMU_B + 0x800 + 4ULL * N), MMR (SMMU_B + 0x1000 + 4ULL * Cb),
      MMR (SMMU_B + 0x1800 + 4ULL * Cb), MMR (CbB), MMR (CbB + 0x30), MMR (CbB + 0x24), MMR (CbB + 0x20), MMR (CbB + 0x38), "@@NL@@");
  return ((R >> 16) & 3) == 0 && (R & 0xFF) == Cb && (MMR (CbB) & 1U) != 0;
}

'''.replace('@@NL@@', NL)
s = s[:a] + code + s[b:]
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
