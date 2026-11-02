p = '<RM9_WORKDIR>/refs/MuChain.c'
s = open(p, encoding='utf-8', newline='').read()
BS = chr(92)

part = open('<RM9_WORKDIR>/refs/panel_part.c', encoding='utf-8').read()
seqs = open('<RM9_WORKDIR>/refs/panel_seq.inc', encoding='utf-8').read()
part = part.replace('@@SEQS@@', seqs)
# the PL format strings in the part use "\n" as a plain argument for %a (like the rest of the file), keep them
marker = 'STATIC VOID\nDumpMemMap (VOID)'
assert marker in s
assert 'PanelMain' not in s
s = s.replace(marker, part + '\n' + marker, 1)

# main: run after the touch setup hook point; NOBOOT = dump/measure only, then stop
old = '  if (!mNoBoot && SelfFileExists (L"' + BS * 2 + 'TOUCH.TXT")) {'
assert old in s
new = ('  if (SelfFileExists (L"' + BS * 2 + 'PANEL.TXT")) {\n    PanelMain ();\n    if (mNoBoot) {\n'
       '      DEBUG ((DEBUG_ERROR, "[MUCHAIN] PANEL.TXT: panel probe done' + BS + 'n"));\n      CpuDeadLoop ();\n      return EFI_SUCCESS;\n    }\n  }\n')
s = s.replace(old, new + old, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)

# scripts: argument 19 = panel mode (p0 = probe only, p60 / p90 / p120)
q = '<RM9_WORKDIR>/refs/make_logdump_img.sh'
t = open(q, encoding='utf-8', newline='').read()
anchor = 'if [ "${17}" = ucsiinit ]'
assert anchor in t
add = ('case "${19}" in p0|p60|p90|p120) echo 1 > /mnt/m/PANEL.TXT;; esac   # DSI panel refresh-rate probe / switch (TE gpio86 measured before and after)\n'
       'if [ "${19}" = p60 ]; then echo 1 > /mnt/m/PANEL60.TXT; fi\n'
       'if [ "${19}" = p90 ]; then echo 1 > /mnt/m/PANEL90.TXT; fi\n'
       'if [ "${19}" = p120 ]; then echo 1 > /mnt/m/PANEL120.TXT; fi\n')
t = t.replace(anchor, add + anchor, 1)
open(q, 'w', encoding='utf-8', newline='').write(t)
q = '<RM9_WORKDIR>/refs/build_muchain.sh'
t = open(q, encoding='utf-8', newline='').read()
a = '"${17}" "${18}"'
assert a in t
t = t.replace(a, '"${17}" "${18}" "${19}"', 1)
open(q, 'w', encoding='utf-8', newline='').write(t)
print('ok')
