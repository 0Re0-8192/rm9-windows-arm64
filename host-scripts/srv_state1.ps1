$py = 'C:\rm9work\py2\Python\Python313\python.exe'; $l = 'C:\rm9work\refs\rm9link.py'
& $py $l put C:\rm9work\state1.ps1 C:\rm9\state1.ps1
& $py $l exec -t 90 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\state1.ps1'
& $py $l get C:\rm9\state1.txt C:\rm9work\grab\state1.txt
