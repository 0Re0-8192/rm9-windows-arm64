p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
BS = chr(92)
NL = BS + 'n'

code = r'''// Let stream id Sid bypass the Apps SMMU: UEFI leaves sCR0.USFCFG = 1 (unmatched stream = fault) and no entry for the QUP wrapper-1 DMA master (0xa3), so its first DMA access is fatal.
// arm-smmu v2 global space: SMR[n] @0x800 + 4n (VALID bit31, MASK 30:16, ID 14:0), S2CR[n] @0xC00 + 4n (TYPE 17:16: 0 translate, 1 bypass, 2 fault).  Writes go to the non-secure alias.
STATIC BOOLEAN
SmmuBypassSid (IN UINT32 Sid)
{
  UINT32  Num = MMR (SMMU_B + 0x20) & 0xFF, I, Idx = 0xFFFFFFFF;

  for (I = Num; I > 0; I--) {
    UINT32  Smr = MMR (SMMU_B + 0x800 + 4ULL * (I - 1)), S2cr = MMR (SMMU_B + 0xC00 + 4ULL * (I - 1));
    if ((Smr & 0x80000000U) == 0 && ((S2cr >> 16) & 3) == 2) {
      Idx = I - 1;
      break;
    }
  }
  if (Idx == 0xFFFFFFFF) {
    PL ("SMMU: no free stream-match entry%a", "@@NL@@");
    return FALSE;
  }
  MMW (SMMU_B + 0xC00 + 4ULL * Idx, 0x00010000);                 // bypass
  MMW (SMMU_B + 0x800 + 4ULL * Idx, 0x80000000U | (Sid & 0x7FFF));
  PL ("SMMU: entry %u written: smr=0x%08x s2cr=0x%08x (wanted 0x%08x / 0x00010000)%a", Idx, MMR (SMMU_B + 0x800 + 4ULL * Idx), MMR (SMMU_B + 0xC00 + 4ULL * Idx), 0x80000000U | (Sid & 0x7FFF), "@@NL@@");
  return MMR (SMMU_B + 0x800 + 4ULL * Idx) == (0x80000000U | (Sid & 0x7FFF)) && ((MMR (SMMU_B + 0xC00 + 4ULL * Idx) >> 16) & 3) == 1;
}

'''.replace('@@NL@@', NL)
m = 'STATIC VOID\nTouchProbe (VOID)'
assert m in s
s = s.replace(m, code + m, 1)

# use it: after SmmuDump, before the GENI init; and always run the transfers if it worked
old = '  SmmuDump (0xA3);\n'
assert old in s
s = s.replace(old, '  SmmuDump (0xA3);\n  if (!SmmuBypassSid (0xA3)) {\n    PL ("TOUCH: could not open the SMMU for the QUP DMA, stopping' + NL + '");\n    return;\n  }\n  SmmuDump (0xA3);\n', 1)
old = '  if (!SelfFileExists (L"' + BS * 2 + 'TOUCHXFER.TXT")) {\n    PL ("TOUCH: transfers skipped (no TOUCHXFER.TXT)' + NL + '");\n    return;\n  }\n'
assert old in s
s = s.replace(old, '', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
