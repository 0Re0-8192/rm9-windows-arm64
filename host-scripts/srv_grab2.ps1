$py = 'C:\rm9work\py2\Python\Python313\python.exe'; $l = 'C:\rm9work\refs\rm9link.py'
foreach ($f in 'C:\rm9\session\shot_1.png','C:\rm9\session\shot_0.png') { & $py $l get $f ('C:\rm9work\grab\' + (Split-Path $f -Leaf)) }
