# phone side of the USB-net throughput test: accept one TCP connection on 5001, count bytes, report (then send 20 MB back)
$l = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Any, 5001); $l.Start()
$c = $l.AcceptTcpClient(); $s = $c.GetStream(); $b = New-Object byte[] 65536; $t = 0
$sw = [Diagnostics.Stopwatch]::StartNew()
while (($n = $s.Read($b, 0, 65536)) -gt 0) { $t += $n }
$sec = $sw.Elapsed.TotalSeconds
"rx $t bytes in $sec s = $([math]::Round($t / 1e6 / $sec, 2)) MB/s" | Out-File C:\rm9\link\net_rx.txt -Encoding ascii
$sw.Restart(); $out = New-Object byte[] 65536; $sent = 0
while ($sent -lt 20MB) { $s.Write($out, 0, 65536); $sent += 65536 }
$s.Flush(); $c.Close(); $l.Stop()
"tx $sent bytes in $($sw.Elapsed.TotalSeconds) s" | Out-File C:\rm9\link\net_tx.txt -Encoding ascii
