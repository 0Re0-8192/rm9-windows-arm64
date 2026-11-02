# wv2check.ps1 - is WebView2 / Edge present?  also SearchHost related services.  Output C:\rm9\wv2check.txt
$o = 'C:\rm9\wv2check.txt'; Remove-Item $o -ErrorAction SilentlyContinue
function W($m) { Add-Content -Path $o -Value $m -Encoding utf8 }
foreach ($p in 'C:\Program Files (x86)\Microsoft\EdgeWebView\Application','C:\Program Files\Microsoft\EdgeWebView\Application','C:\Program Files (x86)\Microsoft\Edge\Application','C:\Program Files\Microsoft\Edge\Application') { W ("{0}: {1}" -f $p, $(if (Test-Path $p) { (Get-ChildItem $p -Directory | Select-Object -ExpandProperty Name) -join ',' } else { 'missing' })) }
foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}','HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}') { $v = (Get-ItemProperty $k -ErrorAction SilentlyContinue).pv; W ("{0}: {1}" -f $k, $v) }
Get-Service WSearch, Dnscache -ErrorAction SilentlyContinue | ForEach-Object { W ("svc {0} {1} {2}" -f $_.Name, $_.Status, $_.StartType) }
W "== WER SearchHost newest"
$d = Get-ChildItem C:\ProgramData\Microsoft\Windows\WER\ReportArchive -Directory | Where-Object { $_.Name -match 'MicrosoftWindows_7486fb27' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($d) { Get-Content (Join-Path $d.FullName 'Report.wer') -Encoding Unicode | Where-Object { $_ -match 'LoadedModule' } | Select-Object -Last 25 | ForEach-Object { W $_ } }
W "== SearchHost dirs"
Get-ChildItem 'C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy' -File | Where-Object { $_.Name -match 'SearchHost|Search\.|Cortana' } | ForEach-Object { W ("{0} {1}" -f $_.Name, $_.Length) }
