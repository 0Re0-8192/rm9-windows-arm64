"""MuChain: \\LONGRUN.TXT => disable the GH watchdog at ExitBootServices (its hardware counter caps at ~32 s, which cut Windows off).
Without LONGRUN.TXT behaviour is unchanged (watchdog stays armed as the safety net)."""
from pathlib import Path

c = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = c.read_text(encoding="utf-8")
assert "mLongRun" not in t
t = t.replace("STATIC BOOLEAN      mNoWp       = FALSE;", "STATIC BOOLEAN      mLongRun    = FALSE;  // \\LONGRUN.TXT: disable the GH watchdog at EBS\nSTATIC BOOLEAN      mNoWp       = FALSE;", 1)
old = "  gBS->ExitBootServices = mOrigExitBs;\n  gBS->Hdr.CRC32 = 0;\n  gBS->CalculateCrc32 (gBS, gBS->Hdr.HeaderSize, &gBS->Hdr.CRC32);\n  {\n    EFI_STATUS Es = mOrigExitBs"
assert old in t
new = '''  if (mLongRun) {
    ARM_SMC_ARGS Wa = { 0 };
    Wa.Arg0 = 0x86000005U;   // GH_WDT_CONTROL
    Wa.Arg1 = 2;             // DISABLE
    ArmCallSmc (&Wa);
    DEBUG ((DEBUG_ERROR, "[MUCHAIN] EBS: LONGRUN: GH_WDT DISABLE ret=%ld (no watchdog from here on)\\n", (INT64)Wa.Arg0));
  }
''' + old
t = t.replace(old, new, 1)
anchor = "  mNoWp   = SelfFileExists (L\"\\\\NOWP.TXT\");"
assert anchor in t
t = t.replace(anchor, anchor + "\n  mLongRun = SelfFileExists (L\"\\\\LONGRUN.TXT\");", 1)
c.write_text(t, encoding="utf-8")

m = Path(r"<RM9_WORKDIR>\refs\make_logdump_img.sh")
s = m.read_text(encoding="utf-8")
if "longrun" not in s:
    s = s.replace('if [ "$4" = nowp ]; then echo 1 > /mnt/m/NOWP.TXT; fi', 'if [ "$4" = nowp ]; then echo 1 > /mnt/m/NOWP.TXT; fi\nif [ "$5" = longrun ]; then echo 1 > /mnt/m/LONGRUN.TXT; fi   # disable GH watchdog at EBS', 1)
    m.write_text(s, encoding="utf-8", newline="\n")
b = Path(r"<RM9_WORKDIR>\refs\build_muchain.sh")
s = b.read_text(encoding="utf-8")
s = s.replace('"$3" "$4"', '"$3" "$4" "$5"')
b.write_text(s, encoding="utf-8", newline="\n")
print("ok")
