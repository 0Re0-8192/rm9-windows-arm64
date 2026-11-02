# spmi.ps1 - read PMIC registers over the SPMI arbiter's observer (read-only; no PMIC write), through rm9io.  Dot-source it:  . .\spmi.ps1
#   Spmi-Init                      builds the ppid -> apid map (arbiter v7, EE0-owned peripherals only)
#   Spmi-Read <sid> <addr16> [n]   n <= 8 bytes, returns a byte array (or $null on failure)
# Same protocol as MuChain.c SpmiReadBytes: cmd EXT_READL into OBSRVR+0x20*apid, poll status bit0, data at +0x18/+0x1C.
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$root\rm9io.ps1"
$script:SPMI_CORE = 0x0C400000; $script:SPMI_CNFG = 0x0C42D000; $script:SPMI_OBSRVR = 0x0C440000
$script:ApidOf = @{}

function Spmi-Init {
    Rm9Open
    $ver = (Rm9Read $SPMI_CORE 1)[0]
    if (($ver -band 0xF0000000) -ne 0x70000000) { throw ("SPMI arbiter version 0x{0:X8} is not v7" -f $ver) }
    $v = Rm9Read ($SPMI_CORE + 0x2000) 1024
    $o = Rm9Read $SPMI_CNFG 1024
    $script:ApidOf = @{}
    for ($a = 0; $a -lt 1024; $a++) {
        if ($v[$a] -eq 0) { continue }
        $ppid = [int](($v[$a] -shr 8) -band 0xFFF)   # [int]: a UInt32 hashtable key never matches the Int32 used by Spmi-Read
        if ((($o[$a] -band 7) -eq 0) -and -not $script:ApidOf.ContainsKey($ppid)) { $script:ApidOf[$ppid] = $a }
    }
    return $script:ApidOf.Count
}

function Spmi-Read([int]$Sid, [int]$Addr16, [int]$Len = 1) {
    $ppid = [int](($Sid -shl 8) -bor ($Addr16 -shr 8))
    if (-not $script:ApidOf.ContainsKey($ppid)) { return $null }
    $off = [uint64]($SPMI_OBSRVR + 0x20 * [int]$script:ApidOf[$ppid])
    $cmd = (1 -shl 27) -bor (($Addr16 -band 0xFF) -shl 4) -bor ($Len - 1)
    Rm9Write $off ([uint32]$cmd)
    $st = 0
    for ($i = 0; $i -lt 200; $i++) {
        $st = (Rm9Read ($off + 8) 1)[0]
        if ($st -band 1) { break }
    }
    if ((($st -band 1) -eq 0) -or (($st -band 0xE) -ne 0)) { return $null }
    $d = Rm9Read ($off + 0x18) 2
    $b = New-Object byte[] $Len
    for ($k = 0; $k -lt $Len; $k++) {
        $w = if ($k -lt 4) { $d[0] } else { $d[1] }
        $b[$k] = ($w -shr (8 * ($k % 4))) -band 0xFF
    }
    return $b
}
