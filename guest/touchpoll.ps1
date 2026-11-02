# S:\rm9\touchpoll.ps1 - run as SYSTEM: start the rm9io touch poller thread (Goodix BRL-D over GENI SE4, set up by MuChain's TOUCH.TXT) and publish the frames.
#   C:\Users\Public\rm9shot\touch.cur  one line, overwritten: "seq;cnt;id0,x0,y0,w0;id1,x1,y1,w1;"   (seq = frame counter; cnt = touch count; the injector in the user session reads it)
#   C:\rm9\touch.log                   every frame: elapsed ms + raw 26 bytes decoded; diag line every 2 s
param([int]$Seconds = 600, [switch]$Quiet)
# $Quiet (boot task): no per-frame log lines, a diag line every 60 s, so the log does not grow
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$root\rm9io.ps1"
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne "Running") { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
Rm9Open
# the pre-boot setup (MuChain TOUCH.TXT) must have run: the SE4 clock gate (GCC_QUP_EN bit 26) and the SMMU entry for stream 0xA3 must be there, otherwise touching SE4 hangs the SoC
$qup = (Rm9Read 0x152008 1)[0]
$sm = Rm9Read 0x15000800 107
$has = $false; foreach ($v in $sm) { if ($v -eq [uint32]2147483811) { $has = $true } }
if ((($qup -band 0x04000000) -eq 0) -or -not $has) {
    New-Item -ItemType Directory -Force C:\rm9 | Out-Null
    "$(Get-Date -Format HH:mm:ss) touch pre-boot setup missing (GCC_QUP_EN=$("{0:X8}" -f $qup) smmu=$has) - poller not started" | Out-File -Append -Encoding ascii C:\rm9\touch.log
    exit 0
}
function Add-Content {
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
    try { $pt = Rm9Read $pa 8 } catch { $pt = @(0xDEAD0000) }
    'smmu: GFSR={0:X8} GFSYNR0..2={1:X8},{2:X8},{3:X8} CB70 SCTLR={4:X8} FSR={5:X8} FAR={6:X8}{7:X8} FSYNR0={8:X8} TTBR0={9:X16} pgd={10}' -f $g[0], $gs[0], $gs[1], $gs[2], $sctlr[0], $c[0], $far[1], $far[0], $fs[0], $pa, (($pt | ForEach-Object { '{0:X8}' -f $_ }) -join ' ')
}
function Ioctl([uint32]$code, [byte[]]$out) {
    $ret = 0
    if (-not [Rm9Io]::DeviceIoControl([Rm9Io]::H, $code, $null, 0, $out, $out.Length, [ref]$ret, [IntPtr]::Zero)) { return $false }
    return $true
}
New-Item -ItemType Directory -Force C:\Users\Public\rm9shot | Out-Null
$log = 'C:\rm9\touch.log'
$cur = 'C:\Users\Public\rm9shot\touch.cur'
$none = New-Object byte[] 0
# pre-flight state, for the log: SMMU entry/context, clock gate, GPIOs, SE4
"=== touchpoll start $(Get-Date -Format 'HH:mm:ss')" | Add-Content $log
"GCC_QUP_EN(0x152008)=$('{0:X8}' -f (Rm9Read 0x152008 1)[0])  SE4 fw_rev(0xA90068)=$('{0:X8}' -f (Rm9Read 0xA90068 1)[0]) status(0xA90040)=$('{0:X8}' -f (Rm9Read 0xA90040 1)[0]) dma_mode(0xA90258)=$('{0:X8}' -f (Rm9Read 0xA90258 1)[0])" | Add-Content $log
foreach ($g in 28,48,49,50,51,161,162) { "gpio$g cfg=$('{0:X8}' -f (Rm9Read (0xF100000 + 0x1000 * $g) 1)[0]) io=$('{0:X8}' -f (Rm9Read (0xF100000 + 0x1000 * $g + 4) 1)[0])" | Add-Content $log }
$sm = Rm9Read 0x15000800 107
$s2 = Rm9Read 0x15000C00 107
for ($i = 0; $i -lt 107; $i++) { if (($sm[$i] -band 0x80000000) -ne 0) { "smr[$i]=$('{0:X8}' -f $sm[$i]) s2cr[$i]=$('{0:X8}' -f $s2[$i])" | Add-Content $log } }
$o = New-Object byte[] 132
if (-not (Ioctl 2399150088 $none)) { "TOUCH_START failed, win32 $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" | Add-Content $log; exit 1 }
$sw = [Diagnostics.Stopwatch]::StartNew()
try { SmmuState | Add-Content $log } catch { "SmmuState failed: $_" | Add-Content $log }
$last = 0; $lastDiag = 0
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    if (-not (Ioctl 2399150092 $o)) { Start-Sleep -Milliseconds 50; continue }
    $seq = [BitConverter]::ToUInt32($o, 0)
    if ($seq -ne $last) {
        $last = $seq
        $f = $o[32..79]
        $cnt = $f[2] -band 0xF
        $pts = ''
        for ($i = 0; $i -lt 5; $i++) {
            $b = 8 + 8 * $i
            $pts += ('{0},{1},{2},{3};' -f ($f[$b] -shr 4), ($f[$b + 2] + 256 * $f[$b + 3]), ($f[$b + 4] + 256 * $f[$b + 5]), ($f[$b + 6] + 256 * $f[$b + 7]))
        }
        $line = "$seq;$cnt;$pts"
        try { [IO.File]::WriteAllText($cur, $line) } catch {}
        if (-not $Quiet) { "$($sw.ElapsedMilliseconds) st=$('{0:X2}' -f $f[0]) $line" | Add-Content $log }
    }
    if ($sw.ElapsedMilliseconds - $lastDiag -gt $(if ($Quiet) { 60000 } else { 2000 })) {
        $lastDiag = $sw.ElapsedMilliseconds
        "$($sw.ElapsedMilliseconds) diag seq=$seq polls=$([BitConverter]::ToUInt32($o, 4)) errors=$([BitConverter]::ToUInt32($o, 8)) running=$([BitConverter]::ToUInt32($o, 12)) lastTd=$('{0:X}' -f [BitConverter]::ToUInt32($o, 16)) lastRd=$('{0:X}' -f [BitConverter]::ToUInt32($o, 20)) lastM=$('{0:X}' -f [BitConverter]::ToUInt32($o, 24)) confirm=$('{0:X8}' -f [BitConverter]::ToUInt32($o, 28)) reinits=$([BitConverter]::ToUInt32($o, 80)) diag[status,clk,ifdis,mirq,mcmd,dmamode,serclk,txst,rxst,txlen,rxlen,txtrans]=" + ((0..11 | ForEach-Object { '{0:X}' -f [BitConverter]::ToUInt32($o, 84 + 4 * $_) }) -join ',') | Add-Content $log
    }
    if ($seq -eq 0 -and $sw.ElapsedMilliseconds -gt 5000 -and -not $script:smmuDone) {
        $script:smmuDone = $true
        try { SmmuState | Add-Content $log } catch { "SmmuState failed: $_" | Add-Content $log }
    }
    Start-Sleep -Milliseconds 2
}
[void](Ioctl 2399150096 $none)
"=== touchpoll end" | Add-Content $log
