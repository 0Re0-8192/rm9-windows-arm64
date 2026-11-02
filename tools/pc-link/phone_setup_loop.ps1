param([switch]$UsbFn, [switch]$Adsp, [switch]$WinDelay, [switch]$Touch, [switch]$UsbPrep, [switch]$Pcie, [string]$Panel = '-', [int]$CaptureWait = 420, [int]$Max = 8, [string]$MuImage = '<RM9_WORKDIR>\out\Mu-fullrun-acpi10sec.img', [switch]$Refresh)
# Unattended: boot Windows on the phone (MuChain LONGRUN, SEC-armed watchdog as recovery) repeatedly until Windows Setup has finished
# (C:\rm9\firstlogon.txt exists on the windows partition) or $Max cycles were used or Android does not come back.
$rm9 = '<RM9_WORKDIR>'
$log = "$rm9\refs\phone_setup_loop.log"
# new PC: another adb device may be attached -> pin the target (adb/fastboot honour ANDROID_SERIAL; WSLENV forwards it through WSL to adb.exe)
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = '<PHONE_SERIAL>' }
if ($env:WSLENV -notmatch 'ANDROID_SERIAL') { $env:WSLENV = (@($env:WSLENV, 'ANDROID_SERIAL') | Where-Object { $_ }) -join ':' }
$py = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'
$sha = (Get-FileHash $MuImage -Algorithm SHA256).Hash.ToLower()
function Reset-Adb {
    # the adb server tends to hang after the phone re-appears: kill it and start a fresh one (with a timeout)
    taskkill /F /IM adb.exe 2>&1 | Out-Null
    Start-Sleep 3
    $j = Start-Job { & 'C:\ADB\adb.exe' start-server 2>&1; & 'C:\ADB\adb.exe' devices 2>&1 }
    if (-not (Wait-Job $j -Timeout 40)) { Stop-Job $j; return $false }
    Receive-Job $j | Out-Null
    return $true
}
function Log($m) { "$(Get-Date -Format 'HH:mm:ss')  $m" | Tee-Object -FilePath $log -Append }
Log "start: max=$Max image=$MuImage"
wsl -d Ubuntu-24.04 -u root -- bash <RM9_WORKDIR>/refs/build_muchain.sh - - - - longrun $(if ($Refresh) { 'refresh' } else { '-' }) - $(if ($UsbFn) { 'usbfn' } else { '-' }) - - - $(if ($Adsp) { 'adsp' } else { '-' }) - - - $(if ($WinDelay) { 'windelay' } else { '-' }) $(if ($Adsp) { 'ucsiinit' } else { '-' }) $(if ($Touch) { 'touch' } else { '-' }) $Panel - $(if ($UsbPrep) { 'usbprep' } else { '-' }) $(if ($Pcie) { 'pcie' } else { '-' }) | Select-Object -Last 1 | ForEach-Object { Log "muchain: $_"; if ($_ -match 'BUILD FAILED') { Log 'STOP: MuChain did not compile - not running a cycle with an old binary'; exit 3 } }
$env:RM9_CAPTURE_WAIT = [string]$CaptureWait
for ($i = 1; $i -le $Max; $i++) {
    $c = ((Get-PSDrive C).Free / 1GB)
    if ($c -lt 5) { Log "STOP: C: free space $([math]::Round($c,1)) GB"; break }
    # clock for Windows (no RTC support yet): local PC time -> S:\rm9\time.txt on the ESP
    Set-Content -Path "$env:TEMP\rm9_time.txt" -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -Encoding ascii
    powershell -NoProfile -ExecutionPolicy Bypass -File "$rm9\refs\esp_put.ps1" -Local "$env:TEMP\rm9_time.txt" -Remote rm9/time.txt | Out-Null
    Log "cycle $i/$Max"
    $out = powershell -NoProfile -ExecutionPolicy Bypass -File "$rm9\refs\muchain_cycle.ps1" -AllowBoot -Label "setup$i" -MuImage $MuImage -MuSha $sha 2>&1 | Select-String -Pattern 'CYCLE|incomplete|refus' | ForEach-Object { $_.Line }
    Log "  cycle result: $($out -join ' | ')"
    Start-Sleep 20; [void](Reset-Adb)
    $b = ''
    try { $b = (& 'C:\ADB\adb.exe' shell getprop sys.boot_completed 2>$null) } catch {}
    if (($b -as [string]).Trim() -ne '1') { Log "STOP: Android not running after cycle $i (manual action may be needed)"; break }
    $g = & $py -I "$rm9\refs\gpt_check_android.py" | Select-String 'CONSISTENT' | Measure-Object | ForEach-Object { $_.Count }
    Log "  GPT consistent LUNs: $g/6"
    if ($g -ne 6) { Log "STOP: GPT check failed"; break }
    $ls = wsl -d Ubuntu-24.04 -u root -- bash -c "cd /root && /root/.venv/bin/python3 <RM9_WORKDIR>/refs/ntfs_remote.py ls rm9 2>&1 | tr '\n' ' '"
    Log "  C:\rm9 = $ls"
    $st = wsl -d Ubuntu-24.04 -u root -- bash -c "cd /root && /root/.venv/bin/python3 <RM9_WORKDIR>/refs/ntfs_remote.py cat Windows/System32/config/SYSTEM /root/SYSTEM.device >/dev/null 2>&1; hivexsh /root/SYSTEM.device <<'EOF' | grep -E 'SetupType|SystemSetupInProgress|OOBEInProgress|CmdLine|SetupPhase' | tr -d '\n'
cd \Setup
lsval
EOF"
    Log "  Setup key: $st"
    if ($ls -match 'run_out\.txt') { Log "run.cmd OUTPUT PRESENT (run_out.txt)"; break }
}
Log "loop end"






