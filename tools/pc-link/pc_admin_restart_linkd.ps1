# ELEVATED (PC): restart the link daemon (it runs elevated, so only an elevated shell can stop it)
Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'python' -and $_.CommandLine -match 'rm9link.py serve' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep 2
schtasks /run /tn rm9linkd | Out-Null
Add-Content <RM9_WORKDIR>\winboot\usbnat.log ("{0} linkd restarted" -f (Get-Date -Format 'HH:mm:ss'))
