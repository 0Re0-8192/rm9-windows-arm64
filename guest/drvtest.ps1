# drvtest.ps1 - install the Qualcomm WCN7850 (FastConnect 7800) Wi-Fi driver from the ESP copy and log what happens.  Output C:\rm9\wifi_drv.txt (read from Android afterwards).
$o = 'C:\rm9\wifi_drv.txt'
function W($m) { "$(Get-Date -Format 'HH:mm:ss') $m" | Out-File -Append -Encoding ascii $o }
function Snap($tag) {
    W "---- $tag"
    try { Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'PCI*' } | Format-List InstanceId, FriendlyName, Class, Status, Problem, ProblemDescription | Out-File -Append -Encoding ascii $o } catch { W "snap err: $_" }
    try { Get-PnpDeviceProperty -InstanceId (Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB*' } | Select-Object -First 1 -ExpandProperty InstanceId) -KeyName 'DEVPKEY_Device_ProblemStatus','DEVPKEY_Device_DriverInfPath','DEVPKEY_Device_Service' -ErrorAction SilentlyContinue | Format-List KeyName, Data | Out-File -Append -Encoding ascii $o } catch { W "prop err: $_" }
    try {
        $id = (Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB*' } | Select-Object -First 1 -ExpandProperty InstanceId)
        if ($id) { W "resources of $id"; pnputil /enum-devices /instanceid "$id" /resources 2>&1 | Out-File -Append -Encoding ascii $o }
        Get-CimInstance Win32_DeviceMemoryAddress | Where-Object { $_.StartingAddress -ge 1610612736 -and $_.StartingAddress -lt 1744830464 } | Format-List Name, StartingAddress, EndingAddress | Out-File -Append -Encoding ascii $o
    } catch { W "res err: $_" }
    try { Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = (Get-Date).AddMinutes(-8) } -MaxEvents 400 -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -match 'qcwlan|Kernel-PnP|Wlan|WiFi|nwifi|Ndis|BugCheck' -or $_.Message -match 'qcwlan|17CB|WCN' } | Select-Object -First 25 | Format-List TimeCreated, ProviderName, Id, Message | Out-File -Append -Encoding ascii $o } catch { W "evt err: $_" }
}
Start-Sleep 90
W 'copying driver from the ESP'
New-Item -ItemType Directory -Force C:\rm9\wcn | Out-Null
Copy-Item -Path 'S:\rm9\wcn\*' -Destination C:\rm9\wcn -Recurse -Force
W ('files copied: ' + (Get-ChildItem C:\rm9\wcn | Measure-Object).Count)
Snap 'before install'
W 'pnputil /add-driver ...'
pnputil /add-driver C:\rm9\wcn\qcwlanhmt8380.inf /install 2>&1 | Out-File -Append -Encoding ascii $o
Start-Sleep 20; Snap 'T+20s after install'
Start-Sleep 60; Snap 'T+80s after install'
Start-Sleep 120; Snap 'T+200s after install'
W 'setupapi log tail'
try { Get-Content C:\Windows\INF\setupapi.dev.log -Tail 60 | Out-File -Append -Encoding ascii $o } catch { W "setupapi err: $_" }
W 'done'
