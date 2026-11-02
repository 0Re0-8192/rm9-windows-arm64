$ErrorActionPreference = 'Continue'
$w = '<RM9_WORKDIR>\winboot'
$st = "$w\BCD_winpe_opts"
Start-Transcript "$w\bcd_opts2_log.txt" -Force | Out-Null
$g = '{cf7d2d5d-c719-11f1-9997-8a6d3b348e4f}'
bcdedit /store $st /set $g sos yes
bcdedit /store $st /set $g bootux disabled
bcdedit /store $st /set $g quietboot no
bcdedit /store $st /enum $g
Stop-Transcript | Out-Null
