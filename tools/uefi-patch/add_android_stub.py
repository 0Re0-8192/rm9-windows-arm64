"""Add the ANDSTUB.TXT bisect to AndroidLaunch: instead of the Android kernel, jump to a 12-instruction stub that fills the framebuffer with magenta and spins.
Magenta panel = the hand-off mechanism (EBS, cache flush, MMU off, branch) works and the problem is Linux / the hardware state Mu leaves; a frozen panel with no change = the mechanism itself fails."""
BS = chr(92) * 2
NL = chr(10)
p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
assert 'ANDSTUB' not in s

# remember the framebuffer size
old = '    mCrumbW      = Gop->Mode->Info->HorizontalResolution;' + NL
assert old in s
s = s.replace(old, old + '    mCrumbBytes  = (UINT64)Gop->Mode->FrameBufferSize;' + NL, 1)
old = 'STATIC UINT32          mCrumbStride, mCrumbW;' + NL
assert old in s
s = s.replace(old, old + 'STATIC UINT64          mCrumbBytes;' + NL, 1)

stub = (
    '  if (Jump && SelfFileExists (L"' + BS + 'ANDSTUB.TXT")) {      // bisect: replace the kernel by a framebuffer-fill stub' + NL +
    '    UINT32 *Code = (UINT32 *)(UINTN)0xA8000000ULL;' + NL +
    '    UINT64 Fb, Cnt;' + NL +
    '    CrumbInit ();' + NL +
    '    Fb  = (UINT64)(UINTN)mCrumbFb;' + NL +
    '    Cnt = mCrumbBytes / 4;' + NL +
    '    Code[0]  = 0xD2800001U | ((UINT32)(Fb & 0xFFFF) << 5);                    // movz x1, fb[15:0]' + NL +
    '    Code[1]  = 0xF2A00001U | ((UINT32)((Fb >> 16) & 0xFFFF) << 5);            // movk x1, fb[31:16], lsl 16' + NL +
    '    Code[2]  = 0xF2C00001U | ((UINT32)((Fb >> 32) & 0xFFFF) << 5);            // movk x1, fb[47:32], lsl 32' + NL +
    '    Code[3]  = 0xD2800002U | ((UINT32)(Cnt & 0xFFFF) << 5);                   // movz x2, count[15:0]' + NL +
    '    Code[4]  = 0xF2A00002U | ((UINT32)((Cnt >> 16) & 0xFFFF) << 5);           // movk x2, count[31:16], lsl 16' + NL +
    '    Code[5]  = 0x52801FE3U | 0;                                               // movz w3, #0x00FF' + NL +
    '    Code[6]  = 0x72A01FE3U | 0;                                               // movk w3, #0x00FF, lsl 16  -> 0x00FF00FF' + NL +
    '    Code[7]  = 0xB8004423U;                                                   // loop: str w3, [x1], #4' + NL +
    '    Code[8]  = 0xF1000442U;                                                   // subs x2, x2, #1' + NL +
    '    Code[9]  = 0x54FFFFC1U;                                                   // b.ne loop' + NL +
    '    Code[10] = 0xD5033F9FU;                                                   // dsb sy' + NL +
    '    Code[11] = 0x14000000U;                                                   // b .' + NL +
    '    ALOG ("ANDSTUB: fb 0x%lx, %lu words" + chr(92) + "n", Fb, Cnt);' + NL +
    '  }' + NL)
stub = stub.replace('" + chr(92) + "n"', BS[0] + 'n"')   # '\n' inside the C string
key = '  if (!Jump) {' + NL + '    goto Done;' + NL + '  }' + NL + '  // 6. hand over'
assert key in s
s = s.replace(key, '  if (!Jump) {' + NL + '    goto Done;' + NL + '  }' + NL + stub + '  // 6. hand over', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok', s.count('ANDSTUB'))
