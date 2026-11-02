# prodcheck.ps1 - one snapshot of the production run: temperature, kick counters, ping, 20 MB download, battery
param([switch]$NoDownload)
. C:\rm9\link\dbgcap.ps1
$o = New-Object System.Collections.Generic.List[string]
$o.Add('time ' + (Get-Date -Format 'HH:mm:ss'))
try {
    $code = [Convert]::ToUInt32('8F002820', 16); $hot = 'n/a'
    if ([DbgCap]::Open()) { $buf = New-Object byte[] 32; $ret = 0; if ([DbgCap]::DeviceIoControl([DbgCap]::H, $code, $buf, 4, $buf, 32, [ref]$ret, [IntPtr]::Zero)) { $hot = ([BitConverter]::ToInt32($buf, 4) / 10.0) } }
    $o.Add("hottest=$hot C")
} catch { $o.Add('temp failed ' + $_.Exception.Message) }
try { $r = DbgIrq 2 0 0 0; $o.Add('irq cnt[0..15]=' + (($r[0..15]) -join ',') + ' pollDpcKicks=' + $r[32] + ' wakes=' + $r[69] + ' bursts=' + $r[66]) } catch { $o.Add('irq failed ' + $_.Exception.Message) }
$p = ping.exe -n 8 -w 2000 192.168.x.x | Select-String 'Lost|Average'; foreach ($l in $p) { $o.Add('gw ' + $l.Line.Trim()) }
$p = ping.exe -n 8 -w 2000 8.8.8.8 | Select-String 'Lost|Average'; foreach ($l in $p) { $o.Add('net ' + $l.Line.Trim()) }
if (-not $NoDownload) {
    foreach ($n in 1..2) { try { $sw = [Diagnostics.Stopwatch]::StartNew(); $wc = New-Object Net.WebClient; $b = $wc.DownloadData('http://speed.cloudflare.com/__down?bytes=20000000'); $sw.Stop(); $o.Add('download ' + [Math]::Round($b.Length * 8 / 1e6 / $sw.Elapsed.TotalSeconds, 1) + ' Mbit/s') } catch { $o.Add('download failed ' + $_.Exception.Message) } }
}
try { $gv = DbgGov 0 0; $bs = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$gv[48]), 0); $o.Add('battery temp (dbgcap) ' + $(if ($bs -eq -32768) { 'n/a' } else { '{0:F2} C' -f ($bs / 100.0) }) + ' budget cap ' + $gv[49] + '/1000, gov on=' + $gv[0] + ' B=' + $gv[1]) } catch { $o.Add('gov failed ' + $_.Exception.Message) }
$o.Add('battlive: ' + ((Get-Content C:\rm9\battlive.log -Tail 1) -join ''))
$o.Add('battwatch: ' + ((Get-Content C:\rm9\battwatch.txt -Tail 1) -join ''))
$o -join "`r`n"
