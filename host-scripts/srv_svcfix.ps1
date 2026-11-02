$py = 'C:\rm9work\py2\Python\Python313\python.exe'; $l = 'C:\rm9work\refs\rm9link.py'
& $py $l put C:\rm9work\svcfix.ps1 C:\rm9\svcfix.ps1
& $py $l exec -t 60 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\svcfix.ps1'
