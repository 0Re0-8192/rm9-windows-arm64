$py = 'C:\rm9work\py2\Python\Python313\python.exe'
$g = '{e29c5a20-d54e-11f1-b697-4c2338c88f0a}'
$cmd = "bcdedit /store S:\EFI\Microsoft\Boot\BCD /bootsequence $g & bcdedit /store S:\EFI\Microsoft\Boot\BCD /enum {bootmgr} & dir C:\w26100.vhdx"
& $py C:\rm9work\refs\rm9link.py exec $cmd
