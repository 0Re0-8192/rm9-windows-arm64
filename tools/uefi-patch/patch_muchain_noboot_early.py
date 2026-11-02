"""MuChain: decide NOBOOT once, at the very start (before anything can write-protect / break the logdump volume)."""
from pathlib import Path

c = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = c.read_text(encoding="utf-8")
assert "mNoBoot" not in t
t = t.replace("STATIC EFI_HANDLE   mSelfVolume = NULL;\n",
              "STATIC EFI_HANDLE   mSelfVolume = NULL;\nSTATIC BOOLEAN      mNoBoot     = TRUE;   // fail safe: stays TRUE until NOBOOT.TXT is positively known to be absent\n", 1)
old = "  DumpProtocolsOnDisks ();\n  UfsProbe ();\n  if (SelfFileExists (L\"\\\\NOBOOT.TXT\")) {"
assert old in t
t = t.replace(old, "  mNoBoot = SelfFileExists (L\"\\\\NOBOOT.TXT\");   // decided BEFORE UfsProbe (a write-protected logdump makes the volume unreadable)\n"
                   "  DumpProtocolsOnDisks ();\n  UfsProbe ();\n  if (mNoBoot) {", 1)
# a deliberate Windows run must be requested explicitly: file \\BOOTOK.TXT on the volume
t = t.replace("  mNoBoot = SelfFileExists (L\"\\\\NOBOOT.TXT\");",
              "  mNoBoot = !SelfFileExists (L\"\\\\BOOTOK.TXT\") || SelfFileExists (L\"\\\\NOBOOT.TXT\");", 1)
c.write_text(t, encoding="utf-8")

m = Path(r"<RM9_WORKDIR>\refs\make_logdump_img.sh")
s = m.read_text(encoding="utf-8")
if "bootok" not in s:
    s = s.replace('if [ "$3" = wptest ]; then echo 1 > /mnt/m/WPTEST.TXT; fi',
                  'if [ "$3" = wptest ]; then echo 1 > /mnt/m/WPTEST.TXT; fi\nif [ "$2" != noboot ]; then echo 1 > /mnt/m/BOOTOK.TXT; fi   # explicit opt-in to start bootmgfw', 1)
    m.write_text(s, encoding="utf-8", newline="\n")
print("ok")
