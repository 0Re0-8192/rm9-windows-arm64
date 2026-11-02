# restest.ps1 - why does the WCN7850 (PCI\VEN_17CB&DEV_1107) fail with CM_PROB_NORMAL_CONFLICT (0xC0000018)?  Dumps the resource requirement vectors (LogConf), the PnP state and the PnP event channels.  Output C:\rm9\wifi_res.txt
$o = 'C:\rm9\wifi_res.txt'
function W($m) { "$(Get-Date -Format 'HH:mm:ss') $m" | Out-File -Append -Encoding ascii $o }
function Hex($b) { if ($b -is [byte[]]) { ($b | ForEach-Object { '{0:x2}' -f $_ }) -join '' } else { "$b" } }
function Dump($tag) {
    W "---- $tag"
    $dev = Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB*' } | Select-Object -First 1
    if (-not $dev) { W 'no VEN_17CB device'; return }
    $id = $dev.InstanceId
    W "device $id status=$($dev.Status) problem=$($dev.Problem)"
    $k = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $id
    foreach ($sub in '', 'LogConf', 'Control', 'Device Parameters', 'Device Parameters\Interrupt Management', 'Device Parameters\Interrupt Management\MessageSignaledInterruptProperties') {
        $p = if ($sub) { "$k\$sub" } else { $k }
        if (-not (Test-Path -LiteralPath $p)) { W "no key $sub"; continue }
        W "key $sub"
        $item = Get-Item -LiteralPath $p
        foreach ($n in $item.GetValueNames()) { W ("  {0} = {1}" -f $n, (Hex $item.GetValue($n))) }
    }
    try { Get-PnpDeviceProperty -InstanceId $id | ForEach-Object { W ("  prop {0} = {1}" -f $_.KeyName, (Hex $_.Data)) } } catch { W "prop err: $_" }
    try { pnputil /enum-devices /instanceid "$id" /resources /relations 2>&1 | Out-File -Append -Encoding ascii $o } catch { W "pnputil err: $_" }
    foreach ($ch in 'Microsoft-Windows-Kernel-PnP/Configuration', 'Microsoft-Windows-Kernel-PnP/Device Management', 'System') {
        W "events $ch"
        try { Get-WinEvent -LogName $ch -MaxEvents 300 -ErrorAction Stop | Where-Object { $_.Message -match '17CB|1107|qcwlan|PCI|ACPI\\PNP0A08|conflict' } | Select-Object -First 12 | Format-List TimeCreated, Id, Message | Out-File -Append -Encoding ascii $o } catch { W "evt err: $_" }
    }
    W 'PCI0 and the other bus devices'
    try { Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'ACPI\PNP0A08*' -or $_.InstanceId -like 'ACPI\PNP0C02*' -or $_.InstanceId -like 'PCI*' } | ForEach-Object { W ("  {0} {1} {2} {3}" -f $_.InstanceId, $_.Status, $_.Problem, $_.FriendlyName) } } catch { W "list err: $_" }
    foreach ($bid in (Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'ACPI\PNP0A08*' } | ForEach-Object { $_.InstanceId })) {
        W "resources of $bid"; pnputil /enum-devices /instanceid "$bid" /resources 2>&1 | Out-File -Append -Encoding ascii $o
    }
    Get-CimInstance Win32_DeviceMemoryAddress | Where-Object { $_.StartingAddress -ge 1610612736 -and $_.StartingAddress -lt 1744830464 } | Format-List Name, StartingAddress, EndingAddress | Out-File -Append -Encoding ascii $o
    Get-CimInstance Win32_IRQResource | Format-List Name, Hardware | Out-File -Append -Encoding ascii $o
}
Start-Sleep 100
Dump 'T+100s'
Start-Sleep 120
Dump 'T+220s'
W 'done'
