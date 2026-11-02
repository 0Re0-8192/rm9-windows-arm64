# itscmd3.ps1 - MAPD (DeviceID 0x1401, Size 9, ITT low) stalled the ITS even with a low ITT.  Try variants, each on a freshly reset command queue (ITS disabled -> CWRITER=0 -> CBASER rewritten -> enabled).
# GITS_TYPER = 0x0003E731: ID_bits = 7 (8 event-ID bits), Devbits = 31.  Windows asked for Size 9 (10 bits) - more than the ITS supports?  Output C:\rm9\wifi_its3.txt  (driver disabled, MSI image)
$o = 'C:\rm9\wifi_its3.txt'
$fs = New-Object IO.FileStream($o, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($m) { $b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss.fff') $m`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) }
function A([string]$h) { [Convert]::ToUInt64($h, 16) }
function U([string]$h) { [Convert]::ToUInt32($h, 16) }
function Hx($a) { ($a | ForEach-Object { '{0:X8}' -f $_ }) -join ' ' }
. C:\rm9\link\rm9io.ps1
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
Start-Sleep 70
L 'itscmd3 start'
$its = A '17140000'
function Its32($off) { (Rm9Read ($its + $off) 1)[0] }
$cb = Its32 0x80
$mask = U 'FFFFF000'
if (($cb -band $mask) -eq 0) { L 'no queue: not touching'; return }
$q = [uint64]($cb -band $mask)
$ctlr0 = Its32 0
L ('CTLR ' + ('{0:X8}' -f $ctlr0) + ' CBASER lo ' + ('{0:X8}' -f $cb) + ' CWRITER ' + ('{0:X8}' -f (Its32 0x88)) + ' CREADR ' + ('{0:X8}' -f (Its32 0x90)))
if (((Its32 0x88) -ne 0) -or ((Its32 0x90) -ne 0)) { L 'queue not empty / stalled: not touching'; return }
$itt = A 'D7FF3000'; $ittLo = U 'D7FF3000'; $V = U '80000000'
function ResetQueue() {
    Rm9Write ($its + 0) ($ctlr0 -band (U 'FFFFFFFE'))          # Enabled = 0
    for ($k = 0; $k -lt 40; $k++) { if (((Its32 0) -band (U '80000000')) -ne 0) { break }; Start-Sleep -Milliseconds 5 }
    Rm9Write ($its + 0x88) 0
    Rm9Write ($its + 0x80) $cb
    Rm9Write ($its + 0) ($ctlr0 -bor 1)                       # Enabled = 1
    Start-Sleep -Milliseconds 20
    L ('  reset: CTLR ' + ('{0:X8}' -f (Its32 0)) + ' CREADR ' + ('{0:X8}' -f (Its32 0x90)) + ' CWRITER ' + ('{0:X8}' -f (Its32 0x88)))
    return ((Its32 0x90) -eq 0)
}
function Cmd([string]$name, [uint32[]]$d) {
    if (-not (ResetQueue)) { L "$name : queue could not be reset, stopping"; return $false }
    for ($i = 0; $i -lt 8; $i++) { Rm9Write ($q + 4 * $i) $d[$i] }
    Rm9Write ($its + 0x88) 0x20
    for ($k = 0; $k -lt 20; $k++) { Start-Sleep -Milliseconds 25; if ((Its32 0x90) -ne 0) { break } }
    $cr = Its32 0x90
    L ("$name : CREADR " + ('{0:X8}' -f $cr) + $(if ($cr -eq 0x20) { '  ACCEPTED' } else { '  STALLED' }))
    return ($cr -eq 0x20)
}
for ($i = 0; $i -lt 1024; $i++) { Rm9Write ($itt + 4 * $i) 0 }
# MAPD: DW0 = 8 | DeviceID<<32 ; DW1 = Size ; DW2 = V<<63 | ITT_addr
[void](Cmd 'SYNC rdbase0' @(5, 0, 0, 0, 0, 0, 0, 0))
[void](Cmd 'MAPD dev=1 size=1' @(8, 1, 1, 0, $ittLo, $V, 0, 0))
[void](Cmd 'MAPD dev=0x1401 size=1' @(8, 0x1401, 1, 0, $ittLo, $V, 0, 0))
[void](Cmd 'MAPD dev=0x1401 size=7' @(8, 0x1401, 7, 0, $ittLo, $V, 0, 0))
[void](Cmd 'MAPD dev=0x1401 size=8' @(8, 0x1401, 8, 0, $ittLo, $V, 0, 0))
[void](Cmd 'MAPD dev=0x1401 size=9' @(8, 0x1401, 9, 0, $ittLo, $V, 0, 0))
[void](Cmd 'MAPD dev=0x1401 size=1 V=0' @(8, 0x1401, 1, 0, $ittLo, 0, 0, 0))
[void](Cmd 'MAPC icid=0 rd=0 V=1' @(9, 0, 0, 0, 0, $V, 0, 0))
[void](Cmd 'INVALL icid=0' @(0x0D, 0, 0, 0, 0, 0, 0, 0))
# put the queue back as Windows had it
[void](ResetQueue)
L ('BASER0 hi ' + ('{0:X8}' -f (Its32 0x104)))
L ('BASER1 hi ' + ('{0:X8}' -f (Its32 0x10C)))
L ('CBASER hi ' + ('{0:X8}' -f (Its32 0x84)))
L ('TYPER hi ' + ('{0:X8}' -f (Its32 0xC)))
L 'done'
