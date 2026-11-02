# C:\rm9\touch\edges.ps1 (SYSTEM, one-shot from touchsup): count edges on the candidate panel-TE pins (TLMM GPIO_IN, bit 0) -> real panel scan rate.
#   gpio86/87/133/137 can carry mdp_vsync (TE input of the MDP); gpio88 = mdp_vsync_e.  TLMM pin n: cfg @ 0xF100000 + 0x1000*n, GPIO_IN/OUT @ +4.
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$root\rm9io.ps1"
Rm9Open
$out = 'C:\rm9\touch\edges.txt'
function W($m) { "$(Get-Date -Format 'HH:mm:ss') $m" | Out-File -Append -Encoding ascii $out }
foreach ($g in 86, 87, 88, 133, 137) {
    $cfg = (Rm9Read (0xF100000 + 0x1000 * $g) 1)[0]
    $inb = New-Object byte[] 16
    [BitConverter]::GetBytes([uint64](0xF100000 + 0x1000 * $g + 4)).CopyTo($inb, 0)
    [BitConverter]::GetBytes([uint32]500).CopyTo($inb, 8)
    [BitConverter]::GetBytes([uint32]1).CopyTo($inb, 12)
    $o = New-Object byte[] 160
    $ret = 0
    $ok = [Rm9Io]::DeviceIoControl([Rm9Io]::H, 2399150100, $inb, 16, $o, 160, [ref]$ret, [IntPtr]::Zero)
    if (-not $ok) { W "gpio$g cfg=$('{0:X8}' -f $cfg) EDGES ioctl failed win32=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())"; continue }
    $rise = [BitConverter]::ToUInt32($o, 0); $fall = [BitConverter]::ToUInt32($o, 4); $smp = [BitConverter]::ToUInt32($o, 8)
    $us = [BitConverter]::ToUInt32($o, 12); $hi = [BitConverter]::ToUInt32($o, 16)
    $ts = @(); for ($i = 0; $i -lt [Math]::Min($rise, 32); $i++) { $ts += [BitConverter]::ToUInt32($o, 32 + 4 * $i) }
    $per = @(); for ($i = 1; $i -lt $ts.Count; $i++) { $per += ($ts[$i] - $ts[$i - 1]) }
    $hz = if ($us -gt 0) { [math]::Round($rise * 1000000.0 / $us, 1) } else { 0 }
    W ("gpio{0} cfg={1:X8} rising={2} falling={3} samples={4} in {5} us high={6} => {7} Hz   periods(us)={8}" -f $g, $cfg, $rise, $fall, $smp, $us, $hi, $hz, ($per -join ','))
}
