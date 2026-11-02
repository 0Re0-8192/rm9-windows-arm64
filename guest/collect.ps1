# C:\rm9\link\collect.ps1 (SYSTEM): one-shot diagnostic bundle for driver work -> C:\rm9\collect\ (the PC fetches it with rm9dev.py collect)
param([int]$Minutes = 30, [string]$Out = 'C:\rm9\collect')
Remove-Item $Out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Out | Out-Null
$since = (Get-Date).AddMinutes(-$Minutes)
function Save($name, $script) { try { & $script 2>&1 | Out-String -Width 250 | Out-File "$Out\$name" -Encoding utf8 } catch { "ERR $_" | Out-File "$Out\$name" } }
Save 'devices_problem.txt' { pnputil /enum-devices /problem }
Save 'devices_all.txt' { Get-PnpDevice | Sort-Object Class, FriendlyName | Format-Table -AutoSize Class, FriendlyName, Status, Present, InstanceId }
Save 'drivers_third_party.txt' { pnputil /enum-drivers }
Save 'setupapi_tail.txt' { Get-Content C:\Windows\INF\setupapi.dev.log -Tail 600 }
Save 'events_system.txt' { Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since; Level = 1, 2, 3 } -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, ProviderName, @{n = 'Message'; e = { ($_.Message -replace '\s+', ' ') } } | Format-List }
Save 'events_pnp.txt' { Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Kernel-PnP/Configuration'; StartTime = $since } -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, @{n = 'Message'; e = { ($_.Message -replace '\s+', ' ') } } | Format-List }
Save 'events_wer.txt' { Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $since; Level = 1, 2 } -ErrorAction SilentlyContinue | Select-Object TimeCreated, Id, ProviderName, @{n = 'Message'; e = { ($_.Message -replace '\s+', ' ') } } | Format-List }
Save 'system.txt' { (Get-CimInstance Win32_OperatingSystem | Select-Object LastBootUpTime, FreePhysicalMemory, TotalVisibleMemorySize | Format-List); Get-Service | Where-Object { $_.Status -eq 'Running' } | Select-Object Name | Format-Table -HideTableHeaders }
Save 'minidumps.txt' { Get-ChildItem C:\Windows\Minidump, C:\Windows\MEMORY.DMP, C:\dedicateddump.sys -ErrorAction SilentlyContinue | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize }
Get-ChildItem $Out | Select-Object Name, Length | Format-Table -AutoSize | Out-String
