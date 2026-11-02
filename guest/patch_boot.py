p = '<RM9_WORKDIR>/refs/winpe/touchpoll.ps1'
s = open(p, encoding='utf-8', newline='').read()
for a, b in (
    ('param([int]$Seconds = 600)\n. S:\\rm9\\rm9io.ps1\nRm9Open\n',
     'param([int]$Seconds = 600, [switch]$Quiet)\n'
     '# $Quiet (boot task): no per-frame log lines, a diag line every 60 s, so the log does not grow\n'
     '$root = Split-Path -Parent $MyInvocation.MyCommand.Path\n'
     '. "$root\\rm9io.ps1"\n'
     'if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne "Running") { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }\n'
     'Rm9Open\n'),
    ('        "$($sw.ElapsedMilliseconds) st=$(\'{0:X2}\' -f $f[0]) $line" | Add-Content $log\n',
     '        if (-not $Quiet) { "$($sw.ElapsedMilliseconds) st=$(\'{0:X2}\' -f $f[0]) $line" | Add-Content $log }\n'),
    ('    if ($sw.ElapsedMilliseconds - $lastDiag -gt 2000) {', '    if ($sw.ElapsedMilliseconds - $lastDiag -gt $(if ($Quiet) { 60000 } else { 2000 })) {'),
):
    assert a in s, a
    s = s.replace(a, b, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
