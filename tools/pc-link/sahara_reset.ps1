param([string]$Port = '')
# Phone sits in Sahara memory-debug mode (ZTE dump). Answer the HELLO (mode 2) and send RESET_REQ so it reboots.
# New PC: COM8 is an unrelated FTDI adapter there, so the port is found by the dump-mode USB ID (19D2:0112) unless -Port is given.
if (-not $Port) {
    $dev = Get-CimInstance Win32_PnPEntity | Where-Object { $_.DeviceID -match 'VID_19D2&PID_0112' -and $_.Name -match '\((COM\d+)\)' }
    if (-not $dev) { throw 'no ZTE dump-mode port (USB 19D2:0112) found; is the phone in ZTE memory dump mode? (or pass -Port COMn)' }
    $Port = ([regex]::Match(@($dev)[0].Name, '\((COM\d+)\)')).Groups[1].Value
    "dump-mode port: $Port ($(@($dev)[0].Name))"
}
function U32([uint32[]]$v) { $o = @(); foreach ($x in $v) { $o += [BitConverter]::GetBytes([uint32]$x) }; return [byte[]]$o }
$sp = New-Object System.IO.Ports.SerialPort $Port, 115200, 'None', 8, 'One'
$sp.ReadTimeout = 2000; $sp.WriteTimeout = 2000
$sp.Open()
try {
    Start-Sleep -Milliseconds 300
    $sp.DiscardInBuffer()
    # HELLO_RESP: cmd=2 len=0x30 version=2 compat=1 status=0 mode=2 + 6 reserved
    $hello = U32 @(2, 0x30, 2, 1, 0, 2, 0, 0, 0, 0, 0, 0)
    $sp.Write($hello, 0, $hello.Length)
    Start-Sleep -Milliseconds 800
    $n = $sp.BytesToRead
    if ($n -gt 0) { $buf = New-Object byte[] $n; [void]$sp.Read($buf, 0, $n); "after HELLO_RESP RX($n): " + (($buf[0..([Math]::Min($n,64)-1)] | ForEach-Object { $_.ToString('X2') }) -join ' ') } else { "after HELLO_RESP RX: nothing" }
    # RESET_REQ: cmd=7 len=8
    $rst = U32 @(7, 8)
    $sp.Write($rst, 0, $rst.Length)
    Start-Sleep -Milliseconds 800
    $n = $sp.BytesToRead
    if ($n -gt 0) { $buf = New-Object byte[] $n; [void]$sp.Read($buf, 0, $n); "after RESET RX($n): " + (($buf[0..([Math]::Min($n,64)-1)] | ForEach-Object { $_.ToString('X2') }) -join ' ') } else { "after RESET RX: nothing" }
} catch { "error: $_" } finally { if ($sp.IsOpen) { $sp.Close() } }
