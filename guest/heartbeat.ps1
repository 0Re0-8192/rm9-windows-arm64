# heartbeat.ps1 - when exactly does the machine stop?  A line every second (write-through) from the start of run.cmd.  Output C:\rm9\wifi_hb.txt
$o = 'C:\rm9\wifi_hb.txt'
$fs = New-Object IO.FileStream($o, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($m) { $b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss.fff') $m`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) }
L ('heartbeat start; uptime s=' + [int]((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalSeconds)
for ($i = 0; $i -lt 400; $i++) {
    $s = (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\qcwlan -ErrorAction SilentlyContinue).Start
    $d = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB*' } | Select-Object -First 1
    L ("t$i qcwlanStart=$s dev=" + $d.Status + '/' + $d.Problem)
    Start-Sleep 1
}
L 'done'
