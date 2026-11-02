# muicheck.ps1 - are the en-US .mui files in System32 at the GA (10.0.28000.1) level?  For each file: which WinSxS version (resources components) does it equal?  Output C:\rm9\muicheck.txt (+ fix list C:\rm9\mui_fix.txt: "dest|src")
param([switch]$Apply)
$o = 'C:\rm9\muicheck.txt'; Remove-Item $o -ErrorAction SilentlyContinue
$fixf = 'C:\rm9\mui_fix.txt'; Remove-Item $fixf -ErrorAction SilentlyContinue
function W($m) { Add-Content -Path $o -Value $m -Encoding utf8 }
$sha = [System.Security.Cryptography.SHA1]::Create()
function Get-Sha1($p) { try { $fs = [IO.File]::Open($p, 'Open', 'Read', 'ReadWrite'); try { ([BitConverter]::ToString($sha.ComputeHash($fs)) -replace '-', '').ToLower() } finally { $fs.Dispose() } } catch { 'ERR' } }
$idx = @{}
Get-ChildItem C:\Windows\WinSxS -Directory | Where-Object { $_.Name -match '^arm64.*_en-us_' } | ForEach-Object {
  $comp = $_.Name
  $v = if ($comp -match '_(10\.0\.28000\.\d+)_') { $Matches[1] } else { '?' }
  Get-ChildItem $_.FullName -Recurse -File -Filter *.mui -ErrorAction SilentlyContinue | ForEach-Object { $k = $_.Name.ToLower(); if (-not $idx[$k]) { $idx[$k] = New-Object System.Collections.ArrayList }; [void]$idx[$k].Add(@($v, $_.FullName)) }
}
W ("indexed mui names: " + $idx.Count)
$n = 0; $ok = 0; $bad = 0; $unk = 0; $fix = @()
$dirs = @('C:\Windows\System32\en-US','C:\Windows\System32\en') + @(Get-ChildItem C:\Windows -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^(WinSxS|servicing|Installer|SoftwareDistribution|assembly|Microsoft.NET|CSC|Logs|Temp|System32|rescache)$' } | ForEach-Object { Get-ChildItem $_.FullName -Directory -Recurse -Depth 3 -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -in 'en-US','en' } | ForEach-Object { $_.FullName } })
W ('dirs: ' + $dirs.Count)
foreach ($dir in $dirs) {
  Get-ChildItem $dir -File -Filter *.mui -ErrorAction SilentlyContinue | ForEach-Object {
    $n++
    $cur = Get-Sha1 $_.FullName
    $c = $idx[$_.Name.ToLower()]
    if (-not $c) { $unk++; return }
    $hit = $null; $ga = $null
    foreach ($e in $c) { $h = Get-Sha1 $e[1]; if ($e[0] -eq '10.0.28000.1') { $ga = $e[1]; $gah = $h }; if ($h -eq $cur) { $hit = $e[0] } }
    if ($hit -eq '10.0.28000.1') { $ok++ }
    elseif ($ga) { $bad++; W ("MISMATCH {0}  current equals {1}  (GA available)" -f $_.FullName.Substring(3), $(if ($hit) { $hit } else { 'none' })); $fix += ($_.FullName + '|' + $ga) }
    else { $unk++ }
  }
}
W ("checked $n : GA-equal $ok, mismatched $bad, no GA candidate/unknown $unk")
$fix | Set-Content $fixf -Encoding utf8
W 'done'
