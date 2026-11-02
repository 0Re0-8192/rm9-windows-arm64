# ecamtest.ps1 - what answers at the real ECAM bus 0 (0x60000000 = DBI = root port) for devices 1..31 (0x60008000 + n*0x8000)?  A line is written BEFORE each read (write-through): the last line is the culprit if the machine stops.  Log S:\rm9\wifi_ecam.txt
$o = 'S:\rm9\wifi_ecam.txt'
$fs = New-Object IO.FileStream($o, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($m) { $b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss.fff') $m`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) }
function A([string]$h) { [Convert]::ToUInt64($h, 16) }
. C:\rm9\link\rm9io.ps1
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
Start-Sleep 70
L 'ecamtest start'
$b = A '60000000'
foreach ($off in 0x0, 0x10, 0x100, 0x7FC) { L ('read dev0 fn0 +0x{0:X}' -f $off); $v = Rm9Read ($b + $off) 1; L ('  = {0:X8}' -f $v[0]) }
foreach ($d in 1..31) {
    $a = $b + ([uint64]$d * 0x8000)
    L ('read dev {0} @{1:X} (id)' -f $d, $a)
    $v = Rm9Read $a 2
    L ('  = {0:X8} {1:X8}' -f $v[0], $v[1])
}
L 'bus 0 devices 1..31 done'
foreach ($f in 1..3) { $a = $b + $f * 0x1000; L ('read dev0 fn{0} @{1:X}' -f $f, $a); $v = Rm9Read $a 2; L ('  = {0:X8} {1:X8}' -f $v[0], $v[1]) }
L 'done'
