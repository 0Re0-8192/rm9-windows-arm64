import re
p = '<RM9_WORKDIR>/refs/winpe/touchpoll.ps1'
s = open(p, encoding='utf-8', newline='').read()
assert '$o = New-Object byte[] 108' in s
s = s.replace('$o = New-Object byte[] 108', '$o = New-Object byte[] 112', 1)
open(p, 'w', encoding='utf-8', newline='').write(s)

# longer window: 28 min session
p = '<RM9_WORKDIR>/refs/winpe/touch_block.txt'
s = open(p, encoding='utf-8').read()
s = s.replace('touchpoll.ps1 -Seconds 840', 'touchpoll.ps1 -Seconds 1560').replace('touchtest.ps1 -Seconds 800', 'touchtest.ps1 -Seconds 1560').replace('touchinject.ps1 -Seconds 820', 'touchinject.ps1 -Seconds 1560')
open(p, 'w', encoding='utf-8').write(s)
p = '<RM9_WORKDIR>/refs/winpe/mk_touch_cmd.py'
s = open(p, encoding='utf-8').read()
if 'shutdown /t 900' not in s:
    s = s.replace("out = base.replace(marker, add + marker, 1)", "out = base.replace(marker, add + marker, 1).replace('shutdown /r /t 900 /f', 'shutdown /r /t 1740 /f')")
open(p, 'w', encoding='utf-8').write(s)
print('ok')
