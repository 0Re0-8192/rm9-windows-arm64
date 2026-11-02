# acl1.ps1 - ACLs of the shell-host package directories and key files (AppContainer access).  Output C:\rm9\acl1.txt
$o = 'C:\rm9\acl1.txt'; Remove-Item $o -ErrorAction SilentlyContinue
function W($m) { Add-Content -Path $o -Value $m -Encoding utf8 }
foreach ($p in 'C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy','C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\SearchHost.exe','C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\resources.pri','C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\Cortana.UI','C:\Windows\SystemApps\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy','C:\Windows\SystemApps\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\StartMenuExperienceHost.exe','C:\Windows\SystemApps\Microsoft.UI.Xaml.CBS_8wekyb3d8bbwe','C:\Windows\SystemApps\MicrosoftWindows.Client.Core_cw5n1h2txyewy','C:\Windows\SystemApps\MicrosoftWindows.Client.Core_cw5n1h2txyewy\resources.pri','C:\Windows\SystemApps\SxS\MicrosoftWindows.58681517.Voiess_cw5n1h2txyewy','C:\Program Files (x86)\Microsoft\EdgeWebView\Application\141.0.3537.71\msedgewebview2.exe','C:\Windows\SystemResources\Windows.UI.Search\Windows.UI.Search.pri') {
  W "=== $p"
  if (Test-Path $p) { (& icacls.exe $p) | Select-Object -First 12 | ForEach-Object { W $_ } } else { W 'missing' }
}
W "=== per-user app data dir of SearchHost (rm9)"
foreach ($p in 'C:\Users\rm9\AppData\Local\Packages\MicrosoftWindows.Client.CBS_cw5n1h2txyewy','C:\Users\rm9\AppData\Local\Packages\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy') {
  W "--- $p exists=$(Test-Path $p)"; if (Test-Path $p) { (& icacls.exe $p) | Select-Object -First 8 | ForEach-Object { W $_ }; Get-ChildItem $p -Force | ForEach-Object { W ("   " + $_.Name) } }
}
W "=== packages (family SID / state)"
Get-AppxPackage -AllUsers -Name 'MicrosoftWindows.Client.CBS','Microsoft.Windows.StartMenuExperienceHost' | ForEach-Object { W ("{0} status={1} nonremovable={2} users={3}" -f $_.PackageFullName, $_.Status, $_.NonRemovable, (($_.PackageUserInformation | ForEach-Object { $_.UserSecurityId.UserName + ':' + $_.InstallState }) -join ',')) }
