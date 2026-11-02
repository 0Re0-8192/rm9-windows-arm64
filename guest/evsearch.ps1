# evsearch.ps1 - every event of the last N minutes mentioning SearchHost/CortanaUI/0x80070005/Access is denied, from all logs.  Output C:\rm9\evsearch.txt
param([int]$Min = 6)
$o = 'C:\rm9\evsearch.txt'; Remove-Item $o -ErrorAction SilentlyContinue
function W($m) { Add-Content -Path $o -Value $m -Encoding utf8 }
$since = (Get-Date).AddMinutes(-$Min)
foreach ($l in Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object { $_.RecordCount -gt 0 -and $_.LastWriteTime -gt $since }) {
  $ev = Get-WinEvent -FilterHashtable @{LogName=$l.LogName; StartTime=$since} -ErrorAction SilentlyContinue | Where-Object { $_.Message -match 'SearchHost|CortanaUI|Cortana|0x80070005|ccess is denied|E_ACCESSDENIED' }
  foreach ($e in ($ev | Select-Object -First 8)) { $m = ($e.Message -replace "`r?`n", ' | '); W ("[{0}] {1:HH:mm:ss} id={2} lvl={3} {4}" -f $l.LogName, $e.TimeCreated, $e.Id, $e.Level, $m.Substring(0, [Math]::Min(420, $m.Length))) }
}
W 'done'
