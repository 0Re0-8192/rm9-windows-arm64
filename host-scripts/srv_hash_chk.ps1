$py = 'C:\rm9work\py2\Python\Python313\python.exe'
$l = 'C:\rm9work\refs\rm9link.py'
& $py $l exec 'tasklist /fi "imagename eq powershell.exe" & dir C:\rm9\vhdx_*.ps1 & dir C:\w26100_remote* & type C:\w26100_remote.md5.progress'
