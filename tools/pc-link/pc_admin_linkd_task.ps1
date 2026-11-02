# ELEVATED (PC), once: start the link daemon (rm9link.py serve --net) elevated at every logon, without a UAC prompt.   Remove: schtasks /delete /tn rm9linkd /f
$py = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'
$u = '<user>-roompc\<user>'
$act = New-ScheduledTaskAction -Execute $py -Argument '<RM9_WORKDIR>\refs\rm9link.py serve --net' -WorkingDirectory '<RM9_WORKDIR>\refs'
$trg = New-ScheduledTaskTrigger -AtLogOn
$pri = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -RunLevel Highest
$set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName 'rm9linkd' -Action $act -Trigger $trg -Principal $pri -Settings $set -Force | Out-Null
Add-Content <RM9_WORKDIR>\winboot\usbnat.log ("{0} task rm9linkd registered" -f (Get-Date -Format 'HH:mm:ss'))
