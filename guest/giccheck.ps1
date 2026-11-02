# giccheck.ps1 - read the GICv3 redistributor registers one at a time (a line is written BEFORE each read; the last line is the culprit if the machine stops).  Log S:\rm9\wifi_gic.txt
$o = 'S:\rm9\wifi_gic.txt'
$fs = New-Object IO.FileStream($o, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($m) { $b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss.fff') $m`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) }
function A([string]$h) { [Convert]::ToUInt64($h, 16) }
. C:\rm9\link\rm9io.ps1
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
Start-Sleep 70
L 'giccheck start'
function RdG($name, [uint64]$addr) { L ("read $name @" + ('{0:X}' -f $addr)); $v = (Rm9Read $addr 1)[0]; L ("  = " + ('{0:X8}' -f $v)); return $v }
$gr = A '17180000'
for ($r = 0; $r -lt 8; $r++) {
    $b = $gr + 0x20000 * $r
    [void](RdG "GICR$r CTLR" $b)
    $tl = RdG "GICR$r TYPER lo" ($b + 8); [void](RdG "GICR$r TYPER hi" ($b + 12))
    [void](RdG "GICR$r PROPBASER lo" ($b + 0x70)); [void](RdG "GICR$r PROPBASER hi" ($b + 0x74))
    [void](RdG "GICR$r PENDBASER lo" ($b + 0x78)); [void](RdG "GICR$r PENDBASER hi" ($b + 0x7C))
}
$pb = (Rm9Read ($gr + 0x70) 1)[0] -band [Convert]::ToUInt32('FFFFF000', 16)
L ("config table @" + ('{0:X}' -f $pb)); [void](RdG 'LPI config[0..3]' $pb)
$pe = (Rm9Read ($gr + 0x78) 1)[0] -band [Convert]::ToUInt32('FFFF0000', 16)
L ("pending table r0 @" + ('{0:X}' -f $pe)); [void](RdG 'pending[0x400]' ([uint64]$pe + 0x400))
L 'done'
