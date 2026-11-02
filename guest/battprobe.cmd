@echo off
rem battprobe.cmd - what does Windows see of the ACPI battery?  (called from run.cmd; output C:\rm9\battprobe.txt)
set O=C:\rm9\battprobe.txt
echo === %date% %time% > %O%
echo --- pnputil battery / ac devices >> %O%
pnputil /enum-devices /class Battery >> %O% 2>&1
pnputil /enum-devices /instanceid "ACPI\PNP0C0A\1" >> %O% 2>&1
echo --- powercfg /batteryreport >> %O%
powercfg /batteryreport /output C:\rm9\batteryreport.html >> %O% 2>&1
echo --- wmic-less battery via PowerShell >> %O%
powershell -NoProfile -Command "try { Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus | Format-List * } catch { 'BatteryStatus: ' + $_ }" >> %O% 2>&1
powershell -NoProfile -Command "try { Get-CimInstance Win32_Battery | Format-List Name,EstimatedChargeRemaining,BatteryStatus,DesignVoltage,FullChargeCapacity } catch { 'Win32_Battery: ' + $_ }" >> %O% 2>&1
powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; $p=[System.Windows.Forms.SystemInformation]::PowerStatus; 'PowerStatus: line=' + $p.PowerLineStatus + ' charge=' + $p.BatteryChargeStatus + ' life%=' + $p.BatteryLifePercent + ' lifeRemainingSec=' + $p.BatteryLifeRemaining" >> %O% 2>&1
echo --- events (Kernel-PnP / ACPI / CmBatt) >> %O%
wevtutil qe System /q:"*[System[Provider[@Name='Microsoft-Windows-Kernel-PnP' or @Name='ACPI' or @Name='CmBatt']]]" /c:15 /f:text /rd:true >> %O% 2>&1
echo done >> %O%
