p = '<RM9_WORKDIR>/refs/winpe/touchpoll.ps1'
s = open(p, encoding='utf-8', newline='').read()

# durable log lines (a forced restart loses ordinary cached writes)
hdr = r'''function Add-Content {
    param([Parameter(Position = 0)]$Path, [Parameter(ValueFromPipeline = $true)]$Value)
    process {
        $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
        $b = [Text.Encoding]::ASCII.GetBytes("$Value`r`n")
        $fs.Write($b, 0, $b.Length); $fs.Dispose()
    }
}
function SmmuState {
    $cb = 0x15080000 + 70 * 0x1000
    $g = Rm9Read 0x15000048 1
    $gs = Rm9Read 0x15000050 3
    $c = Rm9Read ($cb + 0x58) 1
    $far = Rm9Read ($cb + 0x60) 2
    $fs = Rm9Read ($cb + 0x68) 1
    $ttbr = Rm9Read ($cb + 0x20) 2
    $sctlr = Rm9Read $cb 1
    $pa = ([uint64]$ttbr[1] -shl 32) -bor $ttbr[0]
    $pt = Rm9Read $pa 8
    'smmu: GFSR={0:X8} GFSYNR0..2={1:X8},{2:X8},{3:X8} CB70 SCTLR={4:X8} FSR={5:X8} FAR={6:X8}{7:X8} FSYNR0={8:X8} TTBR0={9:X16} pgd={10}' -f $g[0], $gs[0], $gs[1], $gs[2], $sctlr[0], $c[0], $far[1], $far[0], $fs[0], $pa, (($pt | ForEach-Object { '{0:X8}' -f $_ }) -join ' ')
}
'''
marker = 'Rm9Open\n'
assert marker in s
s = s.replace(marker, marker + hdr, 1)

# SMMU state after the START ioctl and with every second diag line
old = '$sw = [Diagnostics.Stopwatch]::StartNew()\n'
assert old in s
s = s.replace(old, old + 'try { SmmuState | Add-Content $log } catch { "SmmuState failed: $_" | Add-Content $log }\n', 1)
old = '    Start-Sleep -Milliseconds 5\n}\n'
assert old in s
s = s.replace(old, '''    if ($seq -eq 0 -and $sw.ElapsedMilliseconds -gt 5000 -and -not $script:smmuDone) {
        $script:smmuDone = $true
        try { SmmuState | Add-Content $log } catch { "SmmuState failed: $_" | Add-Content $log }
    }
''' + old, 1)
open(p, 'w', encoding='utf-8', newline='').write(s)

# short session for the diagnostic run
p = '<RM9_WORKDIR>/refs/winpe/touch_block.txt'
t = open(p, encoding='utf-8').read()
t = t.replace('-Seconds 1560', '-Seconds 300')
open(p, 'w', encoding='utf-8').write(t)
p = '<RM9_WORKDIR>/refs/winpe/mk_touch_cmd.py'
t = open(p, encoding='utf-8').read()
t = t.replace('shutdown /r /t 1740 /f', 'shutdown /r /t 420 /f')
open(p, 'w', encoding='utf-8').write(t)
print('ok')
