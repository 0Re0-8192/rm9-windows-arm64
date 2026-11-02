# itscmd.ps1 - can the GIC ITS read the command queue Windows gave it?  Puts one harmless SYNC command into Windows' own ITS command queue and moves GITS_CWRITER.  Run with the MSI image (IORT+ITS: HAL sets the ITS up at boot, GITS_CBASER then holds the queue address), driver disabled.  Output C:\rm9\wifi_its.txt
$o = 'C:\rm9\wifi_its.txt'
$fs = New-Object IO.FileStream($o, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($m) { $b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss.fff') $m`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) }
function A([string]$h) { [Convert]::ToUInt64($h, 16) }
function Hx($a) { ($a | ForEach-Object { '{0:X8}' -f $_ }) -join ' ' }
. C:\rm9\link\rm9io.ps1
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
Start-Sleep 70
L 'itscmd start'
$its = A '17140000'
function Its32($off) { (Rm9Read ($its + $off) 1)[0] }
L ('GITS CTLR ' + ('{0:X8}' -f (Its32 0)) + ' TYPER ' + ('{0:X8}' -f (Its32 8)))
$cb = @((Its32 0x80), 0)   # CBASER hi (0x84) and TYPER hi (0xC) are not read: unknown whether they stop the machine
L ('CBASER lo ' + (Hx $cb[0]) + ' CWRITER ' + ('{0:X8}' -f (Its32 0x88)) + ' CREADR ' + ('{0:X8}' -f (Its32 0x90)))
$q = [uint64]($cb[0] -band 0xFFFFF000) + ([uint64]$cb[1] -band 0xFFFFF) * 4294967296
if (($cb[0] -band 0xFFFFF000) -eq 0) { L 'CBASER has no queue address (ITS not set up by HAL): not touching'; return }
L ('queue phys ' + ('{0:X}' -f $q) + ' content: ' + (Hx (Rm9Read $q 16)))
$cw = Its32 0x88
if (($cw -ne 0) -or ((Its32 0x90) -ne 0)) { L 'queue not empty / stalled already: not touching'; return }
L 'writing SYNC command (RDbase 0) at queue[0]'
Rm9Write $q 5; Rm9Write ($q + 4) 0; Rm9Write ($q + 8) 0; Rm9Write ($q + 12) 0
Rm9Write ($q + 16) 0; Rm9Write ($q + 20) 0; Rm9Write ($q + 24) 0; Rm9Write ($q + 28) 0
L ('queue now ' + (Hx (Rm9Read $q 8)))
L 'CWRITER = 0x20'
Rm9Write ($its + 0x88) 0x20
for ($i = 0; $i -lt 40; $i++) { Start-Sleep -Milliseconds 25; L ("poll$i CREADR " + ('{0:X8}' -f (Its32 0x90)) + " CWRITER " + ('{0:X8}' -f (Its32 0x88))) }
L 'done'
