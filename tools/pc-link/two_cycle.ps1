# two_cycle.ps1 - the usual Wi-Fi bring-up experiment in one go: (1) boot the ITS-less image and let cleanup_pci.ps1 make Windows forget the Root Port / WCN7850 device nodes (they make the next IORT-enabled boot hang early),
# (2) boot Mu-pcie-rp3 with rpfix.ps1 (ITS stall fixer + Root Port MSI restore + PCI0 restart + qcwlan start + MHI/BHI watch).  Results: bash refs/esp_fetch.sh <dir> wifi_rpfix.txt rp_small.csv
param([string]$Script2 = 'esp_run_rpfix.cmd', [string]$Image2 = '<RM9_WORKDIR>\out\Mu-pcie-rp3.img', [switch]$NoCleanup)
$env:ANDROID_SERIAL = '<PHONE_SERIAL>'
$rm9 = '<RM9_WORKDIR>'
$busy = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'phone_setup_loop|muchain_cycle|run_cycle_bg' -and $_.ProcessId -ne $PID }
if ($busy) { 'busy'; exit 1 }
function Put($name) { powershell -NoProfile -ExecutionPolicy Bypass -File "$rm9\refs\esp_put.ps1" -Local "$rm9\refs\winpe\$name" -Remote rm9/run.cmd | Select-String ' run.cmd' }
function Cycle($img, $tag) {
    $out = Join-Path $env:TEMP "cycle_$tag.out"
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$rm9\refs\run_cycle_bg.ps1" -Out $out -CaptureWait 420 -Pcie -MuImage $img
}
Get-Date -Format HH:mm:ss
if (-not $NoCleanup) {
    Put 'esp_run_cleanup.cmd'
    Cycle "$rm9\out\Mu-pcie-its.img" 'clean'
}
Get-Date -Format HH:mm:ss
Put $Script2
Cycle $Image2 'bringup'
Get-Date -Format HH:mm:ss
