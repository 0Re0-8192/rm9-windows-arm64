# C:\rm9\touch\touchsup.ps1 - SYSTEM boot task: keep the touch injector running in the console user's session (starts it once explorer is up, restarts it if it exits).
param([int]$Seconds = 8640000)
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = 'C:\rm9\touch\touchsup.log'
function L($m) { "$(Get-Date -Format 'HH:mm:ss') $m" | Out-File -Append -Encoding ascii $log }
L "start"
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    try {
        $e = Get-Process explorer -ErrorAction SilentlyContinue
        $i = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*touchinject.ps1*' }
        if ($e -and -not $i) {
            Start-Sleep 5
            $r = & "$root\launch_in_session.ps1" -CommandLine "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $root\touchinject.ps1 -Seconds 8640000"
            L "launch injector: $r"
            if (-not $script:fpsDone -and (Test-Path "$root\fps.ps1")) {
                $script:fpsDone = $true
                $r2 = & "$root\launch_in_session.ps1" -CommandLine "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $root\fps.ps1"
                L "launch fps: $r2"
                try { & "$root\edges.ps1"; L "edges done" } catch { L "edges error: $_" }
                if ((Test-Path "C:\rm9\disp\trial.flag") -and -not (Test-Path "C:\rm9\disp\ok.flag")) {
                    Start-Sleep 30
                    $last = (Get-Content "$root\fps.txt" -ErrorAction SilentlyContinue | Where-Object { $_ -match "DwmFlush.* = ([0-9.]+) Hz" } | Select-Object -Last 1)
                    if ($last -match "= ([0-9.]+) Hz" -and [double]$Matches[1] -ge 45) { "ok" | Out-File "C:\rm9\disp\ok.flag" -Encoding ascii; L "display driver ok: $last" } else { L "display driver NOT ok: $last" }
                }
            }
        }
    } catch { L "error: $_" }
    Start-Sleep 10
}
