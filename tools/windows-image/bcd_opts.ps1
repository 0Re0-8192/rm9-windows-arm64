$ErrorActionPreference = 'Continue'
$w = '<RM9_WORKDIR>\winboot'
$st = "$w\BCD_winpe_opts"
Copy-Item "$w\BCD_from_winpe" $st -Force
Start-Transcript "$w\bcd_opts_log.txt" -Force | Out-Null
$g = '{cf7d2d5d-c719-11f1-9997-8a6d3b348e4f}'
bcdedit /store $st /set $g bootlog yes
bcdedit /store $st /set $g bootstatuspolicy IgnoreAllFailures
bcdedit /store $st /set $g recoveryenabled no
bcdedit /store $st /set $g testsigning on
bcdedit /store $st /set $g bootmenupolicy legacy
bcdedit /store $st /set '{bootmgr}' timeout 0
bcdedit /store $st /enum all
Stop-Transcript | Out-Null
