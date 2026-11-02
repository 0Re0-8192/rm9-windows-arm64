# sysres2.ps1 - the SystemResources *.pri files created in one batch on 2026-10-19 23:36: which WinSxS version (28000.1 GA or an update) do they equal?  Output C:\rm9\sysres2.txt
$o = 'C:\rm9\sysres2.txt'; Remove-Item $o -ErrorAction SilentlyContinue
function W($m) { Add-Content -Path $o -Value $m -Encoding utf8 }
$sha = [System.Security.Cryptography.SHA1]::Create()
function Get-Sha1($p) { try { $fs = [IO.File]::Open($p, 'Open', 'Read', 'ReadWrite'); try { ([BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '').ToLower() } finally { $fs.Dispose() } } catch { 'ERR' } }
# index of every .pri under WinSxS by file name
$idx = @{}
Get-ChildItem C:\Windows\WinSxS -Directory | Where-Object { $_.Name -match '^arm64' } | ForEach-Object {
  $comp = $_.Name
  Get-ChildItem $_.FullName -Recurse -File -Filter *.pri -ErrorAction SilentlyContinue | ForEach-Object { $k = $_.Name.ToLower(); if (-not $idx[$k]) { $idx[$k] = @() }; $idx[$k] += ,@($comp, $_.FullName) }
}
W ("indexed pri names: " + $idx.Count)
Get-ChildItem C:\Windows\SystemResources -Recurse -File -Filter *.pri -Force -ErrorAction SilentlyContinue | Where-Object { $_.CreationTime -ge [datetime]'2026-10-19' } | ForEach-Object {
  $cur = Get-Sha1 $_.FullName
  $cands = $idx[$_.Name.ToLower()]
  $m = @()
  foreach ($c in $cands) { $h = Get-Sha1 $c[1]; $v = if ($c[0] -match '_(10\.0\.28000\.\d+)_') { $Matches[1] } else { '?' }; $m += ("{0}:{1}{2}" -f $v, $h.Substring(0, 8), $(if ($h -eq $cur) { '=CURRENT' } else { '' })) }
  W ("{0} cur={1} | {2}" -f $_.FullName.Substring(26), $cur.Substring(0, 8), ($m -join '  '))
}
W 'done'
