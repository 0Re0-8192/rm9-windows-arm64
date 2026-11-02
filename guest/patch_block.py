p = '<RM9_WORKDIR>/refs/winpe/touch_block.txt'
s = open(p, encoding='utf-8').read()
a = r'copy /y S:\rm9\touchinject.ps1 C:\Users\Public\rm9shot\touchinject.ps1' + '\n'
assert a in s
s = s.replace(a, a + r'copy /y S:\rm9\touchtest.ps1 C:\Users\Public\rm9shot\touchtest.ps1' + '\n', 1)
old = r"& S:\rm9\launch_in_session.ps1 -CommandLine 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\rm9shot\touchinject.ps1"
assert old in s
new = (r"& S:\rm9\launch_in_session.ps1 -CommandLine 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\rm9shot\touchtest.ps1 -Seconds 800'; " + old)
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(s)
print('ok')
