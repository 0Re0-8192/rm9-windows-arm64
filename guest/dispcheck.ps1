# C:\rm9\link\dispcheck.ps1: state of the display driver trial (SYSTEM, run through rm9link exec)
"boot: " + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
"trial.flag: " + (Get-Content C:\rm9\disp\trial.flag -ErrorAction SilentlyContinue) + "  ok.flag: " + (Test-Path C:\rm9\disp\ok.flag) + "  failed.flag: " + (Test-Path C:\rm9\disp\failed.flag)
Get-Content C:\rm9\disp\install.log -Tail 6
Get-CimInstance Win32_VideoController | Select-Object Name, CurrentRefreshRate, CurrentHorizontalResolution, CurrentVerticalResolution, Status | Format-List | Out-String
pnputil /enum-devices /instanceid 'ROOT\BasicDisplay\0000' | Select-String 'Description|Status|Driver Name' | ForEach-Object { $_.Line }
