# itscmd2.ps1 - Windows' first ITS command is MAPD(DeviceID 0x1401, Size 9, ITT 0xA_FFEBB000) and it stalls the ITS.  Hypothesis: the ITT address (above 4 GB) is the problem.
# Issue the same MAPD with the ITT in Mu's reserved scratch page 0xD7FF3000 (below 4 GB) into Windows' own queue and see whether CREADR advances.  Then unmap again.  Output C:\rm9\wifi_its2.txt
$o = 'C:\rm9\wifi_its2.txt'
$fs = New-Object IO.FileStream($o, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($m) { $b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss.fff') $m`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) }
function A([string]$h) { [Convert]::ToUInt64($h, 16) }
function Hx($a) { ($a | ForEach-Object { '{0:X8}' -f $_ }) -join ' ' }
. C:\rm9\link\rm9io.ps1
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
Start-Sleep 70
L 'itscmd2 start'
$its = A '17140000'
function Its32($off) { (Rm9Read ($its + $off) 1)[0] }
$cb = Its32 0x80
L ('CTLR ' + ('{0:X8}' -f (Its32 0)) + ' CBASER lo ' + ('{0:X8}' -f $cb) + ' CWRITER ' + ('{0:X8}' -f (Its32 0x88)) + ' CREADR ' + ('{0:X8}' -f (Its32 0x90)))
if (($cb -band [Convert]::ToUInt32('FFFFF000', 16)) -eq 0) { L 'no queue: not touching'; return }
$q = [uint64]($cb -band [Convert]::ToUInt32('FFFFF000', 16))
if (((Its32 0x88) -ne 0) -or ((Its32 0x90) -ne 0)) { L 'queue not empty / stalled: not touching'; return }
$itt = A 'D7FF3000'
$ittLo = [Convert]::ToUInt32('D7FF3000', 16)
$V = [Convert]::ToUInt32('80000000', 16)
for ($i = 0; $i -lt 1024; $i++) { Rm9Write ($itt + 4 * $i) 0 }
L ('ITT scratch cleared at ' + ('{0:X}' -f $itt))
function Cmd([uint32[]]$d, [uint32]$wr) {
    for ($i = 0; $i -lt 8; $i++) { Rm9Write ($q + [uint64]$wr - 32 + 4 * $i) $d[$i] }
    L ('CWRITER = ' + ('{0:X}' -f $wr))
    Rm9Write ($its + 0x88) $wr
    for ($k = 0; $k -lt 20; $k++) { Start-Sleep -Milliseconds 25; $cr = Its32 0x90; if ($cr -ne ($wr - 32)) { break } }
    L ('  CREADR ' + ('{0:X8}' -f (Its32 0x90)) + ' CWRITER ' + ('{0:X8}' -f (Its32 0x88)))
    return (Its32 0x90)
}
# MAPD: DW0 = opcode 8 | DeviceID<<32 ; DW1 = Size ; DW2 = V<<63 | ITT_addr[51:8]<<8
$r = Cmd @(8, 0x1401, 9, 0, $ittLo, $V, 0, 0) 0x20
if ($r -eq 0x20) {
    L 'MAPD with a low ITT accepted'
    $r = Cmd @(8, 0x1401, 9, 0, $ittLo, 0, 0, 0) 0x40   # unmap again (V=0)
    L 'MAPD V=0 sent'
} else { L 'MAPD with a low ITT is ALSO rejected (Stalled) - ITT address is not the (only) cause' }
L 'done'
