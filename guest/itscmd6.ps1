# itscmd6.ps1 (no queue reset: the ITS registers only take whole 64-bit writes; a 32-bit write to CBASER lo/hi zeroes the other half) - the ITS device table is INDIRECT (GITS_BASER0 hi = 0xF9070000: Valid, Indirect, type Devices, 8-byte entries; L1 = 256 pages at 0x8321C000, all zero where read).
# DeviceID 0x1401 -> L1 index 0x1401/512 = 10 -> L1 entry at 0x8321C000 + 0x50 must point to a valid level-2 page, else MAPD fails.  Does Windows' HAL create that L2 page?  Does a hand-made one fix the stall?
# Log: S:\rm9\wifi_its6.txt (FAT, survives an unclean stop).  Never read GITS offset 0xC (TYPER hi): it stopped the machine.  CBASER must be written as lo AND hi (a lo-only write cleared Valid).
$o = 'S:\rm9\wifi_its6.txt'
$fs = New-Object IO.FileStream($o, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($m) { $b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss.fff') $m`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) }
function A([string]$h) { [Convert]::ToUInt64($h, 16) }
function U([string]$h) { [Convert]::ToUInt32($h, 16) }
function Hx($a) { ($a | ForEach-Object { '{0:X8}' -f $_ }) -join ' ' }
. C:\rm9\link\rm9io.ps1
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
Start-Sleep 70
L 'itscmd6 start'
$its = A '17140000'
function Its32($off) { (Rm9Read ($its + $off) 1)[0] }
$cb = Its32 0x80; $cbh = Its32 0x84
$mask = U 'FFFFF000'
if (($cb -band $mask) -eq 0) { L 'no queue: not touching'; return }
$q = [uint64]($cb -band $mask)
$ctlr0 = Its32 0
L ('CTLR ' + ('{0:X8}' -f $ctlr0) + ' CBASER ' + ('{0:X8}' -f $cbh) + ':' + ('{0:X8}' -f $cb) + ' CWRITER ' + ('{0:X8}' -f (Its32 0x88)) + ' CREADR ' + ('{0:X8}' -f (Its32 0x90)))
L ('BASER0 ' + ('{0:X8}' -f (Its32 0x104)) + ':' + ('{0:X8}' -f (Its32 0x100)) + '  BASER1 ' + ('{0:X8}' -f (Its32 0x10C)) + ':' + ('{0:X8}' -f (Its32 0x108)))
$l1 = A '8321C000'
L ('L1[0..3]   @8321C000: ' + (Hx (Rm9Read $l1 8)))
L ('L1[8..11]  @8321C040: ' + (Hx (Rm9Read ($l1 + 0x40) 8)))
if (((Its32 0x88) -ne 0) -or ((Its32 0x90) -ne 0)) { L 'queue not empty / stalled: not touching'; return }
$itt = A 'D7FF3000'; $ittLo = U 'D7FF3000'; $V = U '80000000'
$script:stalled = $false
$l2 = A 'D7FF4000'; $l2Lo = U 'D7FF4000'
for ($i = 0; $i -lt 1024; $i++) { Rm9Write ($itt + 4 * $i) 0; Rm9Write ($l2 + 4 * $i) 0 }
$script:off = 0
function Cmd([string]$name, [uint32[]]$d) {
    if ($script:stalled) { L "$name : skipped (ITS stalled earlier)"; return $false }
    for ($i = 0; $i -lt 8; $i++) { Rm9Write ($q + $script:off + 4 * $i) $d[$i] }
    $new = $script:off + 32
    Rm9Write ($its + 0x88) $new
    for ($k = 0; $k -lt 20; $k++) { Start-Sleep -Milliseconds 25; $cr = Its32 0x90; if ($cr -ne $script:off) { break } }
    $cr = Its32 0x90
    if ($cr -eq $new) { $script:off = $new; L ("$name : CREADR " + ('{0:X}' -f $cr) + '  ACCEPTED'); return $true }
    $script:stalled = $true
    L ("$name : CREADR " + ('{0:X}' -f $cr) + $(if ($cr -band 1) { '  STALLED' } else { '  NO PROGRESS' }))
    return $false
}
[void](Cmd 'SYNC rdbase0 (harness check)' @(5, 0, 0, 0, 0, 0, 0, 0))
# hand-made level-2 page for DeviceIDs 0x1400..0x15FF (L1[10]); Windows left L1[10] = 0
Rm9Write ($l1 + 0x50) $l2Lo; Rm9Write ($l1 + 0x54) $V
L ('L1[10] now: ' + (Hx (Rm9Read ($l1 + 0x50) 2)))
[void](Cmd 'MAPD dev=0x1401 size=1 with own L2 page' @(8, 0x1401, 1, 0, $ittLo, $V, 0, 0))
[void](Cmd 'MAPD dev=0x1401 size=7' @(8, 0x1401, 7, 0, $ittLo, $V, 0, 0))
[void](Cmd 'MAPD dev=0x1401 size=8' @(8, 0x1401, 8, 0, $ittLo, $V, 0, 0))
[void](Cmd 'MAPD dev=0x1401 size=9' @(8, 0x1401, 9, 0, $ittLo, $V, 0, 0))
L ('L2 entry for 0x1401 after: ' + (Hx (Rm9Read ($l2 + 8) 2)))
L ('final: CTLR ' + ('{0:X8}' -f (Its32 0)) + ' CBASER ' + ('{0:X8}' -f (Its32 0x84)) + ':' + ('{0:X8}' -f (Its32 0x80)) + ' CWRITER ' + ('{0:X8}' -f (Its32 0x88)) + ' CREADR ' + ('{0:X8}' -f (Its32 0x90)))
L 'done (L1[10] left pointing at the hand-made page; the next boot starts clean)'
