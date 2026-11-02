Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'python' -and $_.CommandLine -match 'rm9link.py serve' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep 2
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = 'cmd /c "C:\rm9work\py2\Python\Python313\python.exe C:\rm9work\refs\rm9link.py serve > C:\rm9work\daemon.out 2>&1"' }
"spawn rc=$($r.ReturnValue) pid=$($r.ProcessId)"
Start-Sleep 8
Get-Content C:\rm9work\daemon.out -Tail 15
