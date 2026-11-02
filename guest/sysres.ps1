# sysres.ps1 - is C:\Windows\SystemResources at the GA level?  Output C:\rm9\sysres.txt
$o = 'C:\rm9\sysres.txt'; Remove-Item $o -ErrorAction SilentlyContinue
function W($m) { Add-Content -Path $o -Value $m -Encoding utf8 }
W "== SystemResources\Windows.UI.ShellCommon"
Get-ChildItem C:\Windows\SystemResources\Windows.UI.ShellCommon -Recurse -File -Force | ForEach-Object { W ("{0} {1} created {2:yyyy-MM-dd HH:mm} mod {3:yyyy-MM-dd HH:mm} links={4}" -f $_.FullName.Substring(34), $_.Length, $_.CreationTime, $_.LastWriteTime, (fsutil hardlink list $_.FullName 2>$null | Measure-Object).Count) }
W "== WinSxS shellcommon-ish components"
Get-ChildItem C:\Windows\WinSxS -Directory | Where-Object { $_.Name -match 'shellcommon|startmenu|windows-ui-' } | ForEach-Object { W ("{0}  created {1:yyyy-MM-dd HH:mm}" -f $_.Name, $_.CreationTime) }
W "== SystemResources: files created on 2026-10-19 or later, per top folder"
$h = @{}
Get-ChildItem C:\Windows\SystemResources -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.CreationTime -ge [datetime]'2026-10-19' } | ForEach-Object { $k = $_.FullName.Substring(26).Split('\')[0]; $h[$k] = 1 + [int]$h[$k] }
$h.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object { W ("{0,5} {1}" -f $_.Value, $_.Name) }
W "== total SystemResources files"
W ((Get-ChildItem C:\Windows\SystemResources -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object).Count)
