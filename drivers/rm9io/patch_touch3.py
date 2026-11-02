import re
# ---- driver: 5 contacts (header 8 + 5 x 8 = 48 bytes)
p = '<RM9_WORKDIR>/drv/rm9io/rm9io.c'
s = open(p, encoding='utf-8', newline='').read()
crlf = '\r\n' in s
s = s.replace('\r\n', '\n')
old = '    UINT8  Frame[26];    // last frame with status != 0 (read from 0x10308)\n    UINT8  Pad[2];\n'
assert old in s
s = s.replace(old, '    UINT8  Frame[48];    // last frame with status != 0 (read from 0x10308: 8-byte header + 5 contacts of 8 bytes)\n', 1)
for a, b in (('UCHAR F[26], V[4];', 'UCHAR F[48], V[4];'),
             ('GoodixRd(0x10308, F, 26)', 'GoodixRd(0x10308, F, 48)'),
             ('RtlCopyMemory((PVOID)g_Touch.Frame, F, 26);', 'RtlCopyMemory((PVOID)g_Touch.Frame, F, 48);')):
    assert a in s, a
    s = s.replace(a, b, 1)
if crlf:
    s = s.replace('\n', '\r\n')
open(p, 'w', encoding='utf-8', newline='').write(s)

# ---- poller: frame at 32..79, Reinits at 80, Diag at 84, struct 132 bytes, 5 contacts
p = '<RM9_WORKDIR>/refs/winpe/touchpoll.ps1'
s = open(p, encoding='utf-8', newline='').read()
for a, b in (('$o = New-Object byte[] 112', '$o = New-Object byte[] 132'),
             ('$f = $o[32..57]', '$f = $o[32..79]'),
             ('for ($i = 0; $i -lt 2; $i++) {', 'for ($i = 0; $i -lt 5; $i++) {'),
             ('reinits=$([BitConverter]::ToUInt32($o, 60))', 'reinits=$([BitConverter]::ToUInt32($o, 80))'),
             ('ToUInt32($o, 64 + 4 * $_)', 'ToUInt32($o, 84 + 4 * $_)')):
    assert a in s, a
    s = s.replace(a, b, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)

# ---- injector: up to 5 contacts
p = '<RM9_WORKDIR>/refs/winpe/touchinject.ps1'
s = open(p, encoding='utf-8', newline='').read()
for a, b in (('[Math]::Min($cnt, 2)', '[Math]::Min($cnt, 5)'),
             ('InitializeTouchInjection(5, 1)', 'InitializeTouchInjection(10, 1)')):
    assert a in s, a
    s = s.replace(a, b, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
