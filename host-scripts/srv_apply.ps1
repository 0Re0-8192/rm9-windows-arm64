$py = 'C:\rm9work\py2\Python\Python313\python.exe'
$l = 'C:\rm9work\refs\rm9link.py'
& $py $l put C:\rm9work\refs\apply_start.cmd C:\rm9\apply_start.cmd
& $py $l exec 'C:\rm9\apply_start.cmd'
"cfg sha256:"
(Get-FileHash C:\rm9work\w26100_cfg.vhdx -Algorithm SHA256).Hash.ToLower() | Tee-Object C:\rm9work\w26100_cfg.sha256
