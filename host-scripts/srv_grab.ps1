$py = 'C:\rm9work\py2\Python\Python313\python.exe'; $l = 'C:\rm9work\refs\rm9link.py'
New-Item -ItemType Directory -Force C:\rm9work\grab | Out-Null
foreach ($f in 'C:\rm9\session\shots.txt','C:\rm9\link\agent.txt','C:\rm9\link\linksnap.txt','C:\rm9\acct_run2.txt','C:\rm9\battwatch.txt') {
  $o = 'C:\rm9work\grab\' + (Split-Path $f -Leaf)
  & $py $l get $f $o
}
Get-Content C:\rm9work\grab\shots.txt -Tail 3
