$py = 'C:\rm9work\py2\Python\Python313\python.exe'
$g = '{e29c5a20-d54e-11f1-b697-4c2338c88f0a}'
$cmd = 'copy /y S:\EFI\Microsoft\Boot\BCD S:\rm9\BCD.bak_1101_before_vhdfix & ' +
  "bcdedit /store S:\EFI\Microsoft\Boot\BCD /set $g device vhd=[C:]\w26100.vhdx & " +
  "bcdedit /store S:\EFI\Microsoft\Boot\BCD /set $g osdevice vhd=[C:]\w26100.vhdx & " +
  "bcdedit /store S:\EFI\Microsoft\Boot\BCD /enum $g"
& $py C:\rm9work\refs\rm9link.py exec $cmd
