# rereg.ps1 - re-register the shell packages (this also rebuilds C:\Windows\rescache merged resource maps).  log C:\rm9\rereg.txt
$log = 'C:\rm9\rereg.txt'
function L($m) { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) -Encoding utf8 }
foreach ($n in 'StartMenuExperienceHost','SearchHost','TextInputHost','ShellExperienceHost') { Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
$apps = 'C:\Windows\SystemApps'
foreach ($p in 'Microsoft.UI.Xaml.CBS_8wekyb3d8bbwe','Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy','ShellExperienceHost_cw5n1h2txyewy','MicrosoftWindows.Client.CBS_cw5n1h2txyewy','MicrosoftWindows.Client.Core_cw5n1h2txyewy','MicrosoftWindows.Client.CoreAI_cw5n1h2txyewy','MicrosoftWindows.Client.Photon_cw5n1h2txyewy','MicrosoftWindows.Client.FileExp_cw5n1h2txyewy') {
  $m = Join-Path $apps "$p\AppxManifest.xml"
  if (-not (Test-Path $m)) { L "no manifest $p"; continue }
  try { Add-AppxPackage -Register $m -DisableDevelopmentMode -ErrorAction Stop; L "registered $p" } catch { L "FAILED $p : $($_.Exception.Message -replace "`r?`n",' ')" }
}
L ("rescache files: " + ((Get-ChildItem C:\Windows\rescache -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object).Count))
L 'done'
