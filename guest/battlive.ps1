# battlive.ps1 - keep the ACPI battery block (phys 0xD7FF1000) up to date by talking to the ADSP's battmgr over pmic_glink (channel 8, PMIC_RTR_ADSP_APPS).
#   Run as SYSTEM (rm9io).  Needs MuChain's BattGlinkHandoff block at 0xD7FF1400 ('GLNK'): SMEM descriptor / Tx FIFO / Rx FIFO physical addresses, the ADSP->AP read
#   position and the free ADSP intents left by MuChain's mini glink (same protocol as MuChain.c Mg*, see NEXT.md 0k).
#   Safety: the only physical memory this script writes is (a) the Tx FIFO ring + the descriptor words D[1] (Tx head) / D[2] (Rx tail) that MuChain handed over,
#   (b) the IPCC doorbell it was given, (c) the battery block.  Every address is checked against the handover block before use.
param([int]$Seconds = 8640000, [int]$Period = 5)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$root\rm9io.ps1"
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne "Running") { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
New-Item -ItemType Directory -Force C:\rm9 | Out-Null
$log = "C:\rm9\battlive.log"
function Log($m) { "$(Get-Date -Format 'MM-dd HH:mm:ss') $m" | Out-File -Append -Encoding ascii $log }

function A([string]$hex) { [Convert]::ToUInt64($hex, 16) }          # never type a high hex literal: PowerShell makes it a negative Int32
$BATT = A "D7FF1000"; $GLNK = A "D7FF1400"

$g = Rm9Read $GLNK 9
if ($g[0] -ne 0x4B4E4C47) { Log "no GLNK handoff block (magic 0x$('{0:X8}' -f $g[0])) - not started"; exit 1 }
$D  = [uint64]$g[1]; $TX = [uint64]$g[2]; $RX = [uint64]$g[3]
$pos = [uint32]$g[4]; $free = [uint32]$g[5]
$DB = [uint64]$g[6]; $DBV = [uint32]$g[7]; $MASK = [uint32]$g[8]
# sanity: all three SMEM pieces must lie in the SMEM region MuChain found (0x81D00000 + 2 MB), the doorbell must be the IPCC SEND_ID register
$smLo = A "81D00000"; $smHi = $smLo + 0x200000
foreach ($x in @($D, $TX, $RX)) { if ($x -lt $smLo -or $x -ge $smHi) { Log ("handoff address 0x{0:X} is outside SMEM - refusing" -f $x); exit 2 } }
if ($DB -ne (A "40600C")) { Log ("unexpected doorbell 0x{0:X} - refusing" -f $DB); exit 2 }
Log ("started: D=0x{0:X} TX=0x{1:X} RX=0x{2:X} pos={3} free=0x{4:X}" -f $D, $TX, $RX, $pos, $free)

function RdW([uint64]$base, [uint32]$off) { (Rm9Read ($base + $off) 1)[0] }
function TxWords([uint32[]]$w) {
    $head = RdW $D 4                           # D[1] = Tx head
    foreach ($x in $w) { Rm9Write ($TX + $head) $x; $head = ($head + 4) -band $MASK }
    Rm9Write ($D + 4) $head                    # publish
    Rm9Write $DB $DBV                          # IPCC doorbell: client 3 (ADSP), signal 0 (glink)
}
$script:msg = $null
function Poll {
    # ADSP->AP ring: D[3] = ADSP head; we advance $pos and report it back in D[2]
    $head = RdW $D 12
    $got = $false
    while ($script:pos -ne $head) {
        $avail = ($head - $script:pos) -band $MASK
        if ($avail -lt 8) { break }
        $w0 = RdW $RX $script:pos; $w1 = RdW $RX (($script:pos + 4) -band $MASK)
        $cmd = $w0 -band 0xFFFF; $ch = $w0 -shr 16; $adv = 8
        if ($cmd -eq 9 -or $cmd -eq 12 -or $cmd -eq 13) {
            if ($avail -lt 16) { break }
            $size = RdW $RX (($script:pos + 8) -band $MASK); $left = RdW $RX (($script:pos + 12) -band $MASK)
            $adv = 16 + (($size + 7) -band (-bnot 7))
            if ($avail -lt $adv) { break }
            if ($ch -eq 8) {
                for ($i = 0; $i -lt $size; $i += 4) { $script:asm += , (RdW $RX (($script:pos + 16 + $i) -band $MASK)) }
                if ($left -eq 0) {
                    $script:msg = $script:asm; $script:asm = @(); $got = $true
                    TxWords @([uint32](0x0E -bor (8 -shl 16)), [uint32]$w1)    # RX_DONE_W_REUSE: hand the ADSP's intent back
                }
            }
        } elseif ($cmd -eq 5) { $adv = 8 + 8 * $w1; if ($avail -lt $adv) { break } }
        elseif ($cmd -eq 2) { $adv = 8 + ((($w1 -band 0xFFFF) + 7) -band (-bnot 7)); if ($avail -lt $adv) { break } }
        elseif (($cmd -eq 14 -or $cmd -eq 6) -and $ch -eq 8 -and $w1 -lt 6) { $script:free = $script:free -bor (1 -shl [int]$w1) }
        $script:pos = ($script:pos + $adv) -band $MASK
    }
    Rm9Write ($D + 8) ([uint32]$script:pos)    # D[2] = Rx tail: give the ring space back to the ADSP
    return $got
}
$script:asm = @(); $script:pos = $pos; $script:free = $free
function SendMsg([uint32[]]$payload) {
    $ri = -1
    for ($t = 0; $t -lt 400 -and $ri -lt 0; $t++) {
        [void](Poll)
        for ($i = 0; $i -lt 6; $i++) { if (($script:free -band (1 -shl $i)) -ne 0) { $ri = $i; break } }
        if ($ri -lt 0) { Start-Sleep -Milliseconds 5 }
    }
    if ($ri -lt 0) { return $false }
    $script:free = $script:free -band (-bnot (1 -shl $ri))
    $size = $payload.Count * 4
    $words = @([uint32](9 -bor (8 -shl 16)), [uint32]$ri, [uint32]$size, [uint32]0) + $payload
    if ($words.Count % 2 -ne 0) { $words += [uint32]0 }          # messages are 8-byte aligned
    TxWords $words
    return $true
}
function Prop([uint32]$op, [uint32]$prop) {
    $script:msg = $null
    if (-not (SendMsg @([uint32]0x800A, [uint32]1, $op, [uint32]0, $prop, [uint32]0))) { return $null }
    for ($t = 0; $t -lt 400; $t++) {
        if (Poll) {
            $m = $script:msg
            # reply {0x800A, 1, opcode, property, value, 0}
            if ($m -and $m.Count -ge 5 -and $m[0] -eq 0x800A -and $m[2] -eq $op -and $m[3] -eq $prop) { return [uint32]$m[4] }
        }
        Start-Sleep -Milliseconds 5
    }
    return $null
}
$q = @(@(0x30,0), @(0x30,1), @(0x30,2), @(0x30,4), @(0x30,7), @(0x30,9), @(0x30,0xC), @(0x30,0xD), @(0x30,0xE), @(0x30,0xF), @(0x30,0x10), @(0x30,0x11), @(0x30,0x13), @(0x30,0x1B), @(0x32,0), @(0x32,2), @(0x32,4))
$t0 = Get-Date
$round = 0
while (((Get-Date) - $t0).TotalSeconds -lt $Seconds) {
    $ok = 0
    for ($i = 0; $i -lt $q.Count; $i++) {
        $v = Prop ([uint32]$q[$i][0]) ([uint32]$q[$i][1])
        if ($v -ne $null) { Rm9Write ($BATT + 8 + 8 * $i + 4) $v; $ok++ }
    }
    $round++
    if ($round -le 3 -or $round % 60 -eq 0) { Log ("round {0}: {1}/{2} values updated" -f $round, $ok, $q.Count) }
    if ($ok -eq 0) { Log "no reply from the ADSP in this round" }
    Start-Sleep -Seconds $Period
}
