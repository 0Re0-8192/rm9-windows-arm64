# appxdiag2.ps1 - which SystemApps folders were touched by the 2026-10-19 Windows Update?  Output C:\rm9\appxdiag2.txt
$o = 'C:\rm9\appxdiag2.txt'; Remove-Item $o -ErrorAction SilentlyContinue
function W($m) { Add-Content -Path $o -Value $m -Encoding utf8 }
W "== SystemApps: file creation-time histogram per package (date -> count)"
Get-ChildItem C:\Windows\SystemApps -Directory | ForEach-Object {
  $h = @{}
  Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $k = $_.CreationTime.ToString('yyyy-MM-dd'); $h[$k] = 1 + [int]$h[$k] }
  $s = ($h.GetEnumerator() | Sort-Object Name | ForEach-Object { "{0}:{1}" -f $_.Name, $_.Value }) -join ' '
  W ("{0,-62} {1}" -f $_.Name, $s)
}
W "== AppRepository packages (Client.CBS / StartMenu / Xaml / InpApp)"
Get-ChildItem C:\ProgramData\Microsoft\Windows\AppRepository\Packages -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Client\.CBS|StartMenu|UI\.Xaml|InpApp|Client\.Core|CoreAI' } | ForEach-Object { W ("{0}  created {1}" -f $_.Name, $_.CreationTime) }
W "== SystemApps\SxS"
Get-ChildItem C:\Windows\SystemApps\SxS -Directory -ErrorAction SilentlyContinue | ForEach-Object { W ("{0} created {1}" -f $_.Name, $_.CreationTime) }
W "== WinSxS: appx-ish payloads"
Get-ChildItem C:\Windows\WinSxS -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'client\.cbs|inpapp|startmenuexperience|ui\.xaml\.cbs|textinput' } | Select-Object -First 40 | ForEach-Object { W ("{0} created {1}" -f $_.Name, $_.CreationTime) }
W "== other places"
foreach ($p in 'C:\Windows\InboxApps','C:\Windows\servicing\Packages','C:\Windows\SoftwareDistribution\Download','C:\Windows\WinSxS\Backup') {
  if (Test-Path $p) { W ("{0}: {1} entries" -f $p, (Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Measure-Object).Count) } else { W "$p missing" }
}
W "== done"
