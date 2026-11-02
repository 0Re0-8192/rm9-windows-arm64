$py = 'C:\rm9work\py2\Python\Python313\python.exe'; $l = 'C:\rm9work\refs\rm9link.py'
New-Item -ItemType Directory -Force C:\rm9work\grab2 | Out-Null
& $py $l put C:\rm9work\offline_fix.ps1 C:\rm9\offline_fix.ps1
& $py $l exec -t 240 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\offline_fix.ps1'
& $py $l get C:\rm9\offline_fix.txt C:\rm9work\grab2\offline_fix.txt
