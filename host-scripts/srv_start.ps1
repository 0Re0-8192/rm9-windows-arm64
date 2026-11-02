$py = 'C:\rm9work\py2\Python\Python313\python.exe'
Get-Process python -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep 1
function Spawn($cmd) { $r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd }; "spawn rc=$($r.ReturnValue) pid=$($r.ProcessId)" }
Spawn "cmd /c `"$py C:\rm9work\refs\rm9link.py serve > C:\rm9work\daemon.out 2>&1`""
Start-Sleep 10
& $py C:\rm9work\refs\rm9link.py ping
Spawn "cmd /c `"$py C:\rm9work\refs\rm9put_resume.py C:\rm9work\w26100.vhdx C:\w26100.vhdx auto > C:\rm9work\put.out 2>&1`""
Start-Sleep 20
Get-Content C:\rm9work\w26100.vhdx.put.log -Tail 3
