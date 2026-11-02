Set-Content 'C:\rm9\dp_q.txt' -Encoding ascii @('rescan','select disk 6','online disk','list volume')
diskpart /s 'C:\rm9\dp_q.txt'
Start-Sleep 3
'--- mountvol'
mountvol
'--- Get-Partition'
Get-Partition -DiskNumber 6 -ErrorAction SilentlyContinue | Format-List DiskNumber,PartitionNumber,Type,Size,AccessPaths,IsOffline,IsHidden,NoDefaultDriveLetter | Out-String
'--- events'
Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddMinutes(-5)} -MaxEvents 30 -ErrorAction SilentlyContinue | ForEach-Object { $_.TimeCreated.ToString('HH:mm:ss') + ' ' + $_.ProviderName + ' ' + $_.Id + ' ' + ($_.Message -split "`n")[0] }
