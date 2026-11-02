# stops the GH watchdog pings on purpose (dbgcap IOCTL 8F002820, stop=1); the phone must reset within ~31 s.  Log: C:\rm9\wdtstop.txt
. C:\rm9\link\dbgcap.ps1
function L($s) { ((Get-Date -Format 'HH:mm:ss.fff') + ' ' + $s) | Out-File -Append -Encoding ascii C:\rm9\wdtstop.txt }
function Wdt([uint32]$stop) {
  if (-not [DbgCap]::Open()) { return $null }
  $buf = New-Object byte[] 224
  [BitConverter]::GetBytes($stop).CopyTo($buf, 0)
  $ret = 0
  $code = [Convert]::ToUInt32('8F002820', 16)
  $ok = [DbgCap]::DeviceIoControl([DbgCap]::H, $code, $buf, 4, $buf, 224, [ref]$ret, [IntPtr]::Zero)
  if (-not $ok) { return $null }
  return [BitConverter]::ToUInt32($buf, 0)
}
$on = Wdt 0
L ('guard on=' + $on)
if ($on -ne 1) { L 'guard OFF - not stopping'; exit 2 }
L '*** stopping pings now'
$null = Wdt 1
for ($i = 0; $i -lt 60; $i++) { Start-Sleep 1; L ('alive +' + $i) }
L 'FAIL: still alive'
$null = Wdt 0
