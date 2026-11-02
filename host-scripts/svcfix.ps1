# rebuild the qcwlan service key that wcn_install.ps1 (New-Item -Force) emptied: values as in the INF's QcWlan.Service section, Start stays 4 (rpfix enables it)
$k = 'HKLM:\SYSTEM\CurrentControlSet\Services\qcwlan'
$drv = Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' -Filter 'qcwlanhmt8380.inf_arm64_*' | Select-Object -First 1
$img = '\SystemRoot\System32\DriverStore\FileRepository\' + $drv.Name + '\qcwlanhmt8380.sys'
Set-ItemProperty $k -Name Type -Value 1 -Type DWord
Set-ItemProperty $k -Name ErrorControl -Value 1 -Type DWord
Set-ItemProperty $k -Name ImagePath -Value $img -Type ExpandString
Set-ItemProperty $k -Name DisplayName -Value 'Qualcomm FastConnect 7800 Wi-Fi' -Type String
Set-ItemProperty $k -Name Group -Value 'NDIS' -Type String
Set-ItemProperty $k -Name Start -Value 4 -Type DWord
reg query HKLM\SYSTEM\CurrentControlSet\Services\qcwlan
