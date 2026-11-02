p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
BS = chr(92)
blk = '''  if (SelfFileExists (L"''' + BS*2 + '''RTR.TXT")) {
    Smp2pPublish ();
    gBS->Stall (1000000);
    Smp2pDump ("after-publish");
    RtrOpen (Base, "IPCRTR");
  }
'''
assert blk in s
s = s.replace(blk, '', 1)
anchor = '''  PL ("UCSI probe: PmicGlinkDxe image base 0x%lx''' + BS + '''n", Base);
'''
assert anchor in s
s = s.replace(anchor, anchor + blk, 1)
s = s.replace('for (T = 0; T < 2; T++) {\n      SetMem (Buf0, 48, 0xEE);', 'for (T = 0; T < 10; T++) {\n      SetMem (Buf0, 48, 0xEE);', 1)
s = s.replace('if (T == 2) {\n      PL ("UCSI service never', 'if (T == 10) {\n      PL ("UCSI service never', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
