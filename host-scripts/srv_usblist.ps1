Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'python' } | ForEach-Object { $_.ProcessId.ToString() + ' ' + $_.CreationDate + ' ' + $_.CommandLine }
Get-ChildItem C:\rm9work\*.out,C:\rm9work\*.log,C:\rm9work\*.txt -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 6 | ForEach-Object { $_.Name + ' ' + $_.LastWriteTime }
