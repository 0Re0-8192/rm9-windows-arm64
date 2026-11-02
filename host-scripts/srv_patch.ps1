$py = 'C:\rm9work\py2\Python\Python313\python.exe'
$l = 'C:\rm9work\refs\rm9link.py'
$cfg = 'C:\rm9work\w26100_cfg.vhdx'
"cfg size: " + (Get-Item $cfg).Length
& $py $l get C:\w26100_remote.md5 C:\rm9work\remote.md5
"remote md5 list: " + (Get-Item C:\rm9work\remote.md5).Length
Remove-Item C:\rm9work\patch.bin -ErrorAction SilentlyContinue
& $py C:\rm9work\refs\vhdx_make_patch.py $cfg C:\rm9work\remote.md5 C:\rm9work\patch.bin 4
"patch size: " + (Get-Item C:\rm9work\patch.bin).Length
