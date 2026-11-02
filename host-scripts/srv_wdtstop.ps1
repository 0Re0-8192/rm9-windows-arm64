$py = 'C:\rm9work\py2\Python\Python313\python.exe'; $l = 'C:\rm9work\refs\rm9link.py'
& $py $l ping
& $py $l put C:\rm9work\wdtstop.ps1 C:\rm9\wdtstop.ps1
& $py $l exec -t 5 'powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList ''-NoProfile -ExecutionPolicy Bypass -File C:\rm9\wdtstop.ps1'' -WindowStyle Hidden"'
