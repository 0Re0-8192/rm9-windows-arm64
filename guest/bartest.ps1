# bartest.ps1 - can the CPU read the WCN7850's BAR0 at all?  The driver is disabled (qcwlan Start=4) so Windows has not assigned anything.  Output C:\rm9\wifi_bar.txt (write-through).
# Stage 1: BAR0 = 0x60200000 (inside the root port memory window 0x60200000-0x61FFFFFF), memory space on, read BAR0 words.  No outbound iATU region (keep mode: none, like Android).
# If the machine stops here, the next boot (stage1.started without stage1.done) runs stage 2: the same with an outbound MEM iATU region 2 (0x60200000-0x61FFFFFF 1:1) programmed first.
$o = 'C:\rm9\wifi_bar.txt'
$fs = New-Object IO.FileStream($o, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($m) { $b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss.fff') $m`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) }
function A([string]$h) { [Convert]::ToUInt64($h, 16) }
function Hx($a) { ($a | ForEach-Object { '{0:X8}' -f $_ }) -join ' ' }
. C:\rm9\link\rm9io.ps1
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
Start-Sleep 70
L 'bartest start'
$started = Test-Path C:\rm9\stage1.started
$done = Test-Path C:\rm9\stage1.done
L "stage1.started=$started stage1.done=$done"
L ('EP[00..3C] ' + (Hx (Rm9Read (A '60100000') 16)))
L ('RC[00..3C] ' + (Hx (Rm9Read (A '60000000') 16)))
function Bar($tag) {
    Rm9Write (A '60100010') (A '60200004')
    Rm9Write (A '60100014') 0
    $cmd = (Rm9Read (A '60100004') 1)[0]
    Rm9Write (A '60100004') ($cmd -bor 2)
    L ("$tag BAR0=" + ('{0:X8}' -f (Rm9Read (A '60100010') 1)[0]) + ' cmd=' + ('{0:X8}' -f (Rm9Read (A '60100004') 1)[0]))
    foreach ($off in 0, 4, 8, 0x10, 0x20, 0x40, 0x100) {
        L ("$tag reading BAR0+0x{0:X}" -f $off)
        $v = Rm9Read ((A '60200000') + $off) 1
        L ("$tag BAR0+0x{0:X} = {1:X8}" -f $off, $v[0])
    }
}
if (-not $started) {
    New-Item -ItemType File -Force C:\rm9\stage1.started | Out-Null
    Bar 'S1'
    New-Item -ItemType File -Force C:\rm9\stage1.done | Out-Null
    L 'stage 1 passed'
    $skip = $false
} else { $skip = $true; L 'stage 1 did not finish last time: it stops the machine' }
# stage 2: outbound MEM iATU region 2
L 'stage 2: programming iATU region 2'
$b = A '60001400'
Rm9Write $b 0                         # CTRL1: MEM
Rm9Write ($b + 8)  (A '60200000')     # lower base
Rm9Write ($b + 12) 0
Rm9Write ($b + 16) (A '61FFFFFF')     # limit
Rm9Write ($b + 20) (A '60200000')     # lower target
Rm9Write ($b + 24) 0
Rm9Write ($b + 4)  (A '80000000')     # enable
L ('iATU region 2: ' + (Hx (Rm9Read $b 8)))
Bar 'S2'
L 'stage 2 passed'
Remove-Item C:\rm9\stage1.started, C:\rm9\stage1.done -ErrorAction SilentlyContinue
L 'done'
