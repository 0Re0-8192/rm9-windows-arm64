# pcidiag.ps1 - what does Windows see on PCI0 now that bus 0 has a (shadow) root port?  Log: S:\rm9\wifi_pcidiag.txt (FAT).  Does a scan with an ETW trace (PnP + PCI + ACPI) -> S:\rm9\pci_trace.csv
$o = 'S:\rm9\wifi_pcidiag.txt'
function W($m) { ("$(Get-Date -Format 'HH:mm:ss.fff') $m") | Out-File -Append -Encoding ascii $o }
function A([string]$h) { [Convert]::ToUInt64($h, 16) }
function Hx($a) { ($a | ForEach-Object { '{0:X8}' -f $_ }) -join ' ' }
. C:\rm9\link\rm9io.ps1
if ((Get-Service rm9io -ErrorAction SilentlyContinue).Status -ne 'Running') { Start-Service rm9io -ErrorAction SilentlyContinue; Start-Sleep 1 }
Start-Sleep 70
W 'pcidiag start'
function Dump($tag) {
    W "---- $tag"
    "==== $tag" | Out-File -Append -Encoding ascii S:\rm9\wifi_devs.txt
    pnputil /enum-devices /connected 2>&1 | Out-File -Append -Encoding ascii S:\rm9\wifi_devs.txt
    Get-PnpDevice | Where-Object { $_.InstanceId -match '^(PCI\|ACPI\PNP0A08|ACPI\PNP0C02\50)' } | ForEach-Object { W ("  {0} status={1} problem={2} present={3}" -f $_.InstanceId, $_.Status, $_.Problem, $_.Present) }
    try { Get-PnpDeviceProperty -InstanceId 'ACPI\PNP0A08\0' | Where-Object { $_.KeyName -match 'Problem|DevNodeStatus|Children|Driver|Service' } | ForEach-Object { W ("  PCI0 {0} = {1}" -f $_.KeyName, $_.Data) } } catch { W "PCI0 props: $_" }
    W 'PCI0 resources:'; pnputil /enum-devices /instanceid 'ACPI\PNP0A08\0' /resources /relations 2>&1 | Out-File -Append -Encoding ascii $o
}
Dump 'before scan'
$sh = A '60000000'
W ('RP bus0 dev0 fn0 [00..3F]: ' + (Hx (Rm9Read $sh 16)))
W ('RP bus0 dev0 fn0 [40..7F]: ' + (Hx (Rm9Read ($sh + 0x40) 16)))
W ('bus0 dev1 (0x60008000): ' + (Hx (Rm9Read ($sh + 0x8000) 2)))
W ('EP bus1 dev0 (0x60100000) [00..3F]: ' + (Hx (Rm9Read (A '60100000') 16)))
Remove-Item C:\rm9\pci.etl -ErrorAction SilentlyContinue
logman create trace rm9pci -ets -p 'Microsoft-Windows-Kernel-PnP' 0xFFFFFFFFFFFFFFFF 0xFF -o C:\rm9\pci.etl 2>&1 | Out-Null
logman update trace rm9pci -ets -p 'Microsoft-Windows-PCI' 0xFFFFFFFFFFFFFFFF 0xFF 2>&1 | Out-Null
logman update trace rm9pci -ets -p 'Microsoft-Windows-Kernel-Acpi' 0xFFFFFFFFFFFFFFFF 0xFF 2>&1 | Out-Null
logman update trace rm9pci -ets -p 'Microsoft-Windows-Kernel-Registry' 0xFFFFFFFFFFFFFFFF 0xFF 2>&1 | Out-Null
logman update trace rm9pci -ets -p 'Microsoft-Windows-Kernel-File' 0xFFFFFFFFFFFFFFFF 0xFF 2>&1 | Out-Null
W 'restart PCI0 (re-enumerates the bus)'
pnputil /restart-device 'ACPI\PNP0A08\0' 2>&1 | Out-File -Append -Encoding ascii $o
Start-Sleep 8
Dump 'after scan'
logman stop rm9pci -ets 2>&1 | Out-Null
try { tracerpt C:\rm9\pci.etl -of CSV -o S:\rm9\pci_trace.csv -summary S:\rm9\pci_summary.txt -y 2>&1 | Out-Null } catch {}
Select-String -Path S:\rm9\pci_trace.csv -Pattern 'Microsoft-Windows-Kernel-Registry.*0x00000004, 0x' | Select-Object -First 60000 | ForEach-Object { ($_.Line -replace '\s+', ' ') } | Out-File -Encoding ascii S:\rm9\reg_rows.csv
Select-String -Path S:\rm9\pci_trace.csv -Pattern 'Microsoft-Windows-Kernel-File' | Select-Object -First 40000 | ForEach-Object { ($_.Line -replace '\s+', ' ') } | Out-File -Encoding ascii S:\rm9\file_rows.csv
Select-String -Path S:\rm9\pci_trace.csv -Pattern 'Microsoft-Windows-PCI|Microsoft-Windows-Kernel-PnP' | ForEach-Object { $_.Line } | Out-File -Encoding ascii S:\rm9\pci_small.csv
Remove-Item S:\rm9\pci_trace.csv -ErrorAction SilentlyContinue
foreach ($ch in 'System', 'Microsoft-Windows-Kernel-PnP/Configuration', 'Microsoft-Windows-Kernel-PnP/Device Management') {
    W "events $ch (last 200, filtered)"
    try { Get-WinEvent -LogName $ch -MaxEvents 200 -ErrorAction Stop | Where-Object { $_.Message -match 'PCI|17CB|PNP0A08' } | Select-Object -First 10 | ForEach-Object { W ("  {0} id={1}: {2}" -f $_.TimeCreated.ToString('HH:mm:ss'), $_.Id, (($_.Message -replace "`r?`n", ' | ')).Substring(0, [Math]::Min(400, $_.Message.Length))) } } catch { W "events err: $_" }
}
W 'done'
