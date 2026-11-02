@echo off
rem inventory run: what does Windows see / what failed.  Output -> C:\rm9\run_out.txt, extra files in C:\rm9\inv\
set L=C:\rm9\inv
mkdir %L% 2>nul
echo ==== inventory start %date% %time%
echo [all devices incl. disconnected, with problem codes]
pnputil /enum-devices /problem
echo [ACPI device list]
pnputil /enum-devices /bus ACPI /connected
echo [driver packages loaded (3rd-party/inbox oem)]
pnputil /enum-drivers > %L%\drivers.txt
echo [USB controllers detail]
pnputil /enum-devices /class USB /properties > %L%\usb_props.txt
echo [power / thermal / battery]
powercfg /a > %L%\powercfg_a.txt 2>&1
wmic path win32_battery get /format:list > %L%\battery.txt 2>&1
wmic cpu get Name,NumberOfCores,MaxClockSpeed,CurrentClockSpeed /format:list
wmic memorychip get Capacity,Speed /format:list
wmic computersystem get Manufacturer,Model,TotalPhysicalMemory /format:list
wmic bios get Manufacturer,SMBIOSBIOSVersion,ReleaseDate /format:list
echo [ACPI tables from firmware]
reg query HKLM\HARDWARE\ACPI > %L%\acpi_keys.txt 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Enum\ACPI" /s > %L%\enum_acpi.txt 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Enum\USB" /s > %L%\enum_usb.txt 2>&1
reg query "HKLM\SYSTEM\CurrentControlSet\Enum\URS" /s > %L%\enum_urs.txt 2>&1
echo [recent System errors]
wevtutil qe System /q:"*[System[(Level=1 or Level=2 or Level=3)]]" /c:80 /rd:true /f:text > %L%\ev_sys_errors.txt 2>&1
wevtutil qe Microsoft-Windows-Kernel-PnP/Configuration /c:200 /rd:true /f:text > %L%\ev_pnp_config.txt 2>&1
echo ==== inventory done %date% %time%
shutdown /a
shutdown /r /t 3 /f
