$adb = 'C:\rm9work\adb\adb.exe'
Get-Process adb -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = "cmd /c `"$adb -P 5037 nodaemon server > C:\rm9work\adb_server.out 2>&1`"" }
"spawn rc=$($r.ReturnValue) pid=$($r.ProcessId)"
Start-Sleep 6
& $adb devices
