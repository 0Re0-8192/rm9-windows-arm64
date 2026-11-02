p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
BS = chr(92)
part = open('<RM9_WORKDIR>/refs/usbreplay_part.c', encoding='utf-8').read()
part = part.replace('@@TABLES@@', open('<RM9_WORKDIR>/refs/usbreplay_tables.inc', encoding='utf-8').read())
if 'UsbReplay' in s:
    a = s.index('// ===== USBREPLAY.TXT')
    b = s.index('STATIC VOID\nDumpMemMap (VOID)')
    s = s[:a] + part + '\n' + s[b:]
else:
    marker = 'STATIC VOID\nDumpMemMap (VOID)'
    assert marker in s
    s = s.replace(marker, part + '\n' + marker, 1)
    old = '  if (mNoBoot && SelfFileExists (L"' + BS * 2 + 'USBPWR.TXT")) {'
    assert old in s
    new = ('  if (mNoBoot && SelfFileExists (L"' + BS * 2 + 'USBREPLAY.TXT")) {\n    UsbReplay ();\n'
           '    DEBUG ((DEBUG_ERROR, "[MUCHAIN] USBREPLAY.TXT: replay done' + BS + 'n"));\n    CpuDeadLoop ();\n    return EFI_SUCCESS;\n  }\n')
    s = s.replace(old, new + old, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)

q = '<RM9_WORKDIR>/refs/make_logdump_img.sh'
t = open(q, encoding='utf-8', newline='').read()
anchor = 'if [ "${17}" = ucsiinit ]'
assert anchor in t
if 'USBREPLAY' not in t:
    t = t.replace(anchor, 'if [ "${20}" = usbreplay ]; then echo 1 > /mnt/m/USBREPLAY.TXT; fi   # NOBOOT: replay of Android\'s USB device-mode bring-up\n' + anchor, 1)
    open(q, 'w', encoding='utf-8', newline='').write(t)
q = '<RM9_WORKDIR>/refs/build_muchain.sh'
t = open(q, encoding='utf-8', newline='').read()
a = '"${18}" "${19}"'
assert a in t
if '"${20}"' not in t:
    t = t.replace(a, '"${18}" "${19}" "${20}"', 1)
    open(q, 'w', encoding='utf-8', newline='').write(t)
print('ok')
