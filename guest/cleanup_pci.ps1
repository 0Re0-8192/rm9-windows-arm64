# cleanup_pci.ps1 - forget the root port / WCN7850 device nodes that Windows remembers from the bring-up runs (run in a boot with the ITS-less image Mu-pcie-its.img, where nothing uses the ITS).  Log S:\rm9\wifi_cleanup.txt
$o = 'S:\rm9\wifi_cleanup.txt'
function W($m) { ("$(Get-Date -Format 'HH:mm:ss.fff') $m") | Out-File -Append -Encoding ascii $o }
Start-Sleep 60
W 'cleanup start'
$k = 'HKLM:\SYSTEM\CurrentControlSet\Enum\PCI'
Get-ChildItem $k | Where-Object { $_.PSChildName -match 'VEN_17CB' } | ForEach-Object { W ("key " + $_.PSChildName + ': ' + (($_.GetSubKeyNames()) -join ' ')) }
$ids = Get-PnpDevice | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB*' } | ForEach-Object { $_.InstanceId }
foreach ($id in $ids) {
    W "remove-device $id"
    pnputil /remove-device "$id" 2>&1 | Out-File -Append -Encoding ascii $o
}
Start-Sleep 5
W 'after remove:'
Get-PnpDevice | Where-Object { $_.InstanceId -like 'PCI*VEN_17CB*' } | ForEach-Object { W ("  " + $_.InstanceId + ' status=' + $_.Status + ' present=' + $_.Present) }
Get-ChildItem $k | Where-Object { $_.PSChildName -match 'VEN_17CB' } | ForEach-Object { W ("key " + $_.PSChildName + ': ' + (($_.GetSubKeyNames()) -join ' ')) }
# numproc 1 removed: with one CPU the stall fixer cannot run in parallel with the PCI0 restart, the ITS stays stalled and the hypervisor stops (clock freezes)
W 'numproc removed (back to all CPUs)'
(bcdedit /deletevalue '{current}' numproc 2>&1) -join ' ' | ForEach-Object { W $_ }
W 'done'
shutdown /a
shutdown /r /t 5 /f
