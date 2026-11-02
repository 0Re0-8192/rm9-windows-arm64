p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
BS = chr(92)

geni = open('<RM9_WORKDIR>/winboot/touch2/geni_spi.c', encoding='utf-8').read()
# fix the interrupt-enable constants and the error mask (see review)
old = '0x3FC0007E | 0xC00000 | 0x3000000 | 0x30000000 | 0x4000000 | 0x8000000 | 1U | 0x40000000'
assert old in geni
geni = geni.replace(old, '0x7FC0007F', 1)
old = '(St & 0x3E000000U) != 0 || (St & 0x3E) != 0'
assert old in geni
geni = geni.replace(old, '(St & 0x3300003EU) != 0', 1)
probe = open('<RM9_WORKDIR>/winboot/touch2/touch_probe_part.c', encoding='utf-8').read()

# power-down at the end of the probe (RPMh votes survive a warm reboot in the AOP)
down = '''
STATIC VOID
TouchPowerDown (VOID)
{
  UINT32  A = CmdDbAddr ("ldob14");

  PcGpio (161, 0x200, 0);
  PcGpio (28, 0x200, 0);
  if (A != 0) {
    RpmhWrite (A + 0x4, 0);                     // AVDD off again
  }
  MMW (GCC_QUP_EN, MMR (GCC_QUP_EN) & ~(1U << 26));
  PL ("TOUCH: powered down%a", "\\n");
}
'''
probe = probe.replace('\\n', BS + 'n') if False else probe
marker = 'STATIC VOID\nDumpMemMap (VOID)'
assert marker in s
s = s.replace(marker, geni + probe + down + '\n' + marker, 1)

# call from main, next to the USBPWR NOBOOT branch
old = '  if (mNoBoot && SelfFileExists (L"' + BS * 2 + 'USBPWR.TXT")) {'
assert old in s
new = ('  if (mNoBoot && SelfFileExists (L"' + BS * 2 + 'TOUCH.TXT")) {\n    TouchProbe ();\n    TouchPowerDown ();\n'
       '    DEBUG ((DEBUG_ERROR, "[MUCHAIN] TOUCH.TXT: touch probe done' + BS + 'n"));\n    CpuDeadLoop ();\n    return EFI_SUCCESS;\n  }\n') + old
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)

# scripts: argument 18 = touch
q = '<RM9_WORKDIR>/refs/make_logdump_img.sh'
t = open(q, encoding='utf-8', newline='').read()
t = t.replace('if [ "${17}" = ucsiinit ]', 'if [ "${18}" = touch ]; then echo 1 > /mnt/m/TOUCH.TXT; fi   # NOBOOT: Goodix touch bring-up probe over GENI SE4 SPI\nif [ "${17}" = ucsiinit ]', 1)
open(q, 'w', encoding='utf-8', newline='').write(t)
q = '<RM9_WORKDIR>/refs/build_muchain.sh'
t = open(q, encoding='utf-8', newline='').read()
t = t.replace('"${16}" "${17}"', '"${16}" "${17}" "${18}"', 1)
open(q, 'w', encoding='utf-8', newline='').write(t)
print('ok')
