$py = 'C:\rm9work\py2\Python\Python313\python.exe'
$l = 'C:\rm9work\refs\rm9link.py'
& $py $l exec 'del C:\patch.bin C:\patch.bin.applied C:\patch.bin.progress 2>nul & echo cleaned'
Remove-Item C:\rm9work\patch.bin.put.log -ErrorAction SilentlyContinue
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = "cmd /c `"$py C:\rm9work\refs\rm9put_resume.py C:\rm9work\patch.bin C:\patch.bin 0 > C:\rm9work\patchput.out 2>&1`"" }
"spawn rc=$($r.ReturnValue) pid=$($r.ProcessId)"
