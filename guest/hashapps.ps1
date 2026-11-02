# hashapps.ps1 - "relpath|size|sha1" of every file under C:\Windows\SystemApps (live state) -> C:\rm9\apps_live.txt
$o = 'C:\rm9\apps_live.txt'
$root = 'C:\Windows\SystemApps'
$sha = [System.Security.Cryptography.SHA1]::Create()
$w = New-Object System.IO.StreamWriter($o, $false, (New-Object System.Text.UTF8Encoding($false)))
$n = 0
Get-ChildItem $root -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $h = ''
  try { $fs = [System.IO.File]::Open($_.FullName, 'Open', 'Read', 'ReadWrite'); try { $h = ([BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '').ToLower() } finally { $fs.Dispose() } } catch { $h = 'ERR' }
  $w.WriteLine(($_.FullName.Substring($root.Length + 1) + '|' + $_.Length + '|' + $h))
  $n++
}
$w.Dispose()
Add-Content 'C:\rm9\apps_live_done.txt' ("done $n files " + (Get-Date))
