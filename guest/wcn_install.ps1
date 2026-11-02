# S:\rm9\wcn_install.ps1 (SYSTEM): stage the Wi-Fi (qcwlan) driver WITHOUT letting it load.  `pnputil /install` binds the driver to the present endpoint (PCI VEN_17CB DEV_1107)
# and qcwlan then freezes Windows (interrupts only work through the polling build), so: disable the endpoint, install, set Start=4, enable (the driver stays unloaded; rpfix enables it later).
$o = 'S:\rm9\wcn_install.txt'
function W($m) { ("$(Get-Date -Format 'HH:mm:ss.fff') $m") | Out-File -Append -Encoding ascii $o }
$svc = 'HKLM:\SYSTEM\CurrentControlSet\Services\qcwlan'
if (Test-Path $svc) { Set-ItemProperty -Path $svc -Name Start -Value 4 -Type DWord }  # (never New-Item -Force on an existing key: it empties it)
Set-ItemProperty -Path $svc -Name Start -Value 4 -Type DWord -ErrorAction SilentlyContinue
W 'Start=4 (before install)'
$ep = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like 'PCI\VEN_17CB&DEV_1107*' }
foreach ($d in $ep) { W ('disable ' + $d.InstanceId); Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue }
W 'pnputil add-driver /install'
pnputil /add-driver C:\rm9\wcn\qcwlanhmt8380.inf /install 2>&1 | ForEach-Object { W ('  ' + $_) }
Set-ItemProperty -Path $svc -Name Start -Value 4 -Type DWord -ErrorAction SilentlyContinue
W ('Start now = ' + (Get-ItemProperty $svc -ErrorAction SilentlyContinue).Start)
foreach ($d in $ep) { W ('enable ' + $d.InstanceId); Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false -ErrorAction SilentlyContinue }
W 'done'
