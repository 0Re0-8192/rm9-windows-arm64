# Boot the phone into Windows with the resident PC link and wait until the agent answers (about 2 minutes).  ONE cycle only.
#   powershell -File refs\rm9_up.ps1            then:  python refs\rm9link.py exec "ver" | put | get | reboot
# Prerequisites: ESP run.cmd = refs\winpe\esp_run_linkboot.cmd (esp_put.ps1), UsbDk installed on the PC.  Windows stays up until `rm9link reboot` (or the 40-minute safety restart if run.cmd's timer was not cancelled: rm9link exec "shutdown /a").
param([int]$CaptureWait = 2700, [switch]$Touch, [switch]$Pcie, [string]$MuImage = '')
$busy = Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'powershell|python' -and $_.CommandLine -match 'phone_setup_loop|muchain_cycle|Run-Cycle2' -and $_.ProcessId -ne $PID }
if ($busy) { Write-Output "a cycle is already running (pid $($busy.ProcessId -join ',')): not starting another"; exit 1 }
$out = Join-Path $env:TEMP 'rm9_up_cycle.out'
$args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '<RM9_WORKDIR>\refs\run_cycle_bg.ps1', '-Out', $out, '-CaptureWait', $CaptureWait)
if ($Touch) { $args2 += '-Touch' }
if ($Pcie) { $args2 += '-Pcie' }
if ($MuImage) { $args2 += @('-MuImage', $MuImage) }
Start-Process powershell -ArgumentList $args2 -WindowStyle Hidden
$py = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'
& $py '<RM9_WORKDIR>\refs\rm9link.py' wait
