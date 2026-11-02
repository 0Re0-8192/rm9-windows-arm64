# wer1.ps1 - dump the newest WER report of each crashing shell host (incl. stowed exception info) to C:\rm9\wer1.txt
$o = 'C:\rm9\wer1.txt'; Remove-Item $o -ErrorAction SilentlyContinue
function W($m) { Add-Content -Path $o -Value $m -Encoding utf8 }
$dirs = Get-ChildItem C:\ProgramData\Microsoft\Windows\WER\ReportArchive -Directory | Sort-Object LastWriteTime -Descending
$seen = @{}
foreach ($d in $dirs) {
  $p = ($d.Name -split '_')[1]
  if ($seen[$p]) { continue }
  $seen[$p] = 1
  W "=== $($d.Name) $($d.LastWriteTime)"
  Get-ChildItem $d.FullName | ForEach-Object { W ("  file {0} {1}" -f $_.Name, $_.Length) }
  $r = Join-Path $d.FullName 'Report.wer'
  if (Test-Path $r) { Get-Content $r -Encoding Unicode | Select-Object -First 140 | ForEach-Object { W $_ } }
}
W "== LocalDumps key"
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps' -ErrorAction SilentlyContinue | Out-String | ForEach-Object { W $_ }
