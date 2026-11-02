# crashnow.ps1 - shell-host crashes in the last N minutes + which hosts are running now.  Output C:\rm9\crashnow.txt
param([int]$Min = 5)
$o = 'C:\rm9\crashnow.txt'; Remove-Item $o -ErrorAction SilentlyContinue
function W($m) { Add-Content -Path $o -Value $m -Encoding utf8 }
W ("now " + (Get-Date))
$since = (Get-Date).AddMinutes(-$Min)
$ev = Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000; StartTime=$since} -ErrorAction SilentlyContinue
W ("crash events (id 1000) in last $Min min: " + @($ev).Count)
$ev | Group-Object { ($_.Message -split "`n")[0] } | ForEach-Object { W ("  {0} x{1}" -f $_.Name.Trim(), $_.Count) }
$ev | Select-Object -First 3 | ForEach-Object { W ("  last: {0:HH:mm:ss} {1}" -f $_.TimeCreated, (($_.Message -replace "`r?`n", ' | ').Substring(0, 300))) }
foreach ($n in 'StartMenuExperienceHost','SearchHost','TextInputHost','ShellExperienceHost','explorer','sihost') {
  $p = Get-Process -Name $n -ErrorAction SilentlyContinue
  W ("proc {0}: {1}" -f $n, $(if ($p) { ($p | ForEach-Object { "pid$($_.Id) start " + $_.StartTime.ToString('HH:mm:ss') }) -join ', ' } else { 'not running' }))
}
