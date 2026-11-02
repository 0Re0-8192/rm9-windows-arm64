p = '<RM9_WORKDIR>/refs/winpe/touchpoll.ps1'
s = open(p, encoding='utf-8', newline='').read()
old = '$o = New-Object byte[] 60'
assert old in s
s = s.replace(old, '$o = New-Object byte[] 108', 1)
old = ' confirm=$(\'{0:X8}\' -f [BitConverter]::ToUInt32($o, 28))" | Add-Content $log'
assert old in s
new = (' confirm=$(\'{0:X8}\' -f [BitConverter]::ToUInt32($o, 28)) reinits=$([BitConverter]::ToUInt32($o, 60)) diag[status,clk,ifdis,mirq,mcmd,dmamode,serclk,txst,rxst,txlen,rxlen,txtrans]=" + '
       '((0..11 | ForEach-Object { \'{0:X}\' -f [BitConverter]::ToUInt32($o, 64 + 4 * $_) }) -join \',\') | Add-Content $log')
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
