# hb2.ps1 - when does the machine stop?  A line every second to the ESP (FAT, write-through) starting as early as run.cmd allows.  Output S:\rm9\wifi_hb2.txt
$o = 'S:\rm9\wifi_hb2.txt'
$fs = New-Object IO.FileStream($o, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($m) { $b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss.fff') $m`r`n"); $fs.Write($b, 0, $b.Length); $fs.Flush($true) }
. C:\rm9\link\rm9io.ps1
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
function Hx($a) { ($a | ForEach-Object { '{0:X8}' -f $_ }) -join ' ' }
L ('hb2 start; uptime s=' + [int]((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalSeconds)
$dbi = [Convert]::ToUInt64('60000000', 16)
L ('RP cfg [00..3F]: ' + (Hx (Rm9Read $dbi 16)))
L ('RP cfg [40..7F]: ' + (Hx (Rm9Read ($dbi + 0x40) 16)))
L ('RP MISC_CONTROL_1 ' + ('{0:X8}' -f (Rm9Read ($dbi + 0x8BC) 1)[0]))
for ($i = 0; $i -lt 400; $i++) {
    $s = (Get-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\qcwlan -ErrorAction SilentlyContinue).Start
    $d = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB*' }
    L ("t$i qcwlanStart=$s " + (($d | ForEach-Object { $_.InstanceId.Substring(0, 24) + '=' + $_.Status + '/' + $_.Problem }) -join ' '))
    Start-Sleep 1
}
L 'done'
