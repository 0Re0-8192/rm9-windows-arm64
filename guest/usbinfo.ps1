# S:\rm9\usbinfo.ps1 - collect the Windows-side USB state into C:\rm9\session\usbinfo.txt
$o = 'C:\rm9\session\usbinfo.txt'
function H($t) { Add-Content -Path $o -Value ("`r`n######## " + $t) }
function P($x) { Add-Content -Path $o -Value ($x | Out-String -Width 220).TrimEnd() }
H 'USB-related devices (all, present or not)'
P (Get-PnpDevice | Where-Object { $_.InstanceId -match 'QCOM0C8B|URS|USB|UCM|UCSI|PNP0CA1|QCOMFFE1|TYPEC|USBFN' -or $_.Class -match 'USB|UCM|UsbFn' } | Sort-Object Class, InstanceId | Format-Table Class, Status, Present, Problem, FriendlyName, InstanceId -AutoSize)
H 'ACPI devices (whole list, to see what Type-C / PD / battery related nodes exist)'
P (Get-PnpDevice -Class * | Where-Object { $_.InstanceId -like 'ACPI*' } | Sort-Object InstanceId | Format-Table Status, FriendlyName, InstanceId -AutoSize)
foreach ($id in 'ACPI\QCOM0C8B\0') {
    H "properties of $id"
    P (Get-PnpDeviceProperty -InstanceId $id | Where-Object { $_.Data -ne $null } | ForEach-Object { '{0} = {1}' -f $_.KeyName, (($_.Data | Out-String).Trim() -replace '\s+', ' ') })
}
H 'xHCI host child + root hub properties'
foreach ($d in (Get-PnpDevice | Where-Object { $_.InstanceId -like 'URS*HOST*' -or $_.InstanceId -like 'USB\ROOT_HUB30*' })) {
    Add-Content -Path $o -Value ('--- ' + $d.InstanceId + ' status=' + $d.Status)
    P (Get-PnpDeviceProperty -InstanceId $d.InstanceId | Where-Object { $_.KeyName -match 'Power|Capab|Address|Location|Problem|DevNodeStatus|Bus|Parent|Children|Stack|Driver' } | ForEach-Object { '{0} = {1}' -f $_.KeyName, (($_.Data | Out-String).Trim() -replace '\s+', ' ') })
}
H 'allocated resources (IRQ / memory) of the USB controller nodes'
try {
    $dev = Get-CimInstance Win32_PnPEntity | Where-Object { $_.PNPDeviceID -match 'QCOM0C8B|URS' }
    foreach ($d in $dev) {
        Add-Content -Path $o -Value ('--- ' + $d.PNPDeviceID)
        P (Get-CimAssociatedInstance -InputObject $d -ResultClassName Win32_IRQResource -ErrorAction SilentlyContinue | Select-Object IRQNumber, Hardware, TriggerType, TriggerLevel)
        P (Get-CimAssociatedInstance -InputObject $d -ResultClassName Win32_DeviceMemoryAddress -ErrorAction SilentlyContinue | Select-Object StartingAddress, EndingAddress)
    }
} catch { Add-Content -Path $o -Value ('resource query failed: ' + $_.Exception.Message) }
H 'USB controllers / hubs (CIM)'
P (Get-CimInstance Win32_USBController | Select-Object Name, Status, PNPDeviceID)
P (Get-CimInstance Win32_USBHub | Select-Object Name, Status, PNPDeviceID)
H 'registry: USB device enum + related services'
foreach ($k in 'HKLM:\SYSTEM\CurrentControlSet\Enum\USB', 'HKLM:\SYSTEM\CurrentControlSet\Enum\URS', 'HKLM:\SYSTEM\CurrentControlSet\Enum\USBFN') {
    Add-Content -Path $o -Value ('--- ' + $k)
    try { P (Get-ChildItem $k -Recurse -ErrorAction Stop | Select-Object -ExpandProperty Name) } catch { Add-Content -Path $o -Value '(none)' }
}
foreach ($s in 'UrsSynopsys', 'UrsCx01000', 'USBXHCI', 'UcmUcsiAcpiClient', 'UcmUcsiCx0101', 'UcmCx0101', 'UcmTcpciCx0101', 'ufxsynopsys', 'Ufx01000') {
    Add-Content -Path $o -Value ('--- service ' + $s)
    try { P (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$s" -ErrorAction Stop | Select-Object ImagePath, Start, Type, DependOnService) } catch { Add-Content -Path $o -Value '(not installed)' }
    try { P (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$s\Parameters" -ErrorAction Stop) } catch { }
}
H 'registry: USB global settings'
P (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\USB' -ErrorAction SilentlyContinue)
H 'System event log: USB / PnP / URS (this boot)'
try {
    P (Get-WinEvent -LogName System -MaxEvents 400 -ErrorAction Stop | Where-Object { $_.ProviderName -match 'USB|URS|UFX|UCM|Kernel-PnP|UserPnp|Wdf' } | Select-Object -First 60 | ForEach-Object { '{0} {1} {2}: {3}' -f $_.TimeCreated.ToString('HH:mm:ss'), $_.ProviderName, $_.Id, (($_.Message -replace '\s+', ' ')).Substring(0, [Math]::Min(180, $_.Message.Length)) })
} catch { Add-Content -Path $o -Value ('event log failed: ' + $_.Exception.Message) }
H 'power'
P (powercfg /devicequery wake_armed 2>&1)
H 'done'
