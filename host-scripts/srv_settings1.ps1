$py = 'C:\rm9work\py2\Python\Python313\python.exe'; $l = 'C:\rm9work\refs\rm9link.py'
& $py $l put C:\rm9work\settings1.cmd C:\rm9\settings1.cmd
& $py $l exec -t 90 'C:\rm9\settings1.cmd'
& $py $l get C:\rm9\settings1.txt C:\rm9work\grab\settings1.txt
& $py $l get C:\rm9\session\shots.txt C:\rm9work\grab\shots.txt
$last = (Get-Content C:\rm9work\grab\shots.txt -Tail 1) -split ' ' | Select-Object -Index 1
"newest: $last"
& $py $l get ('C:\rm9\session\' + $last) C:\rm9work\grab\settings1_shot.png
