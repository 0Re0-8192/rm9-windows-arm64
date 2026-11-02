# appxdiag.ps1 - why do StartMenuExperienceHost / SearchHost / TextInputHost crash?  Output: C:\rm9\appxdiag.txt (run as SYSTEM via rm9link exec).
$o = 'C:\rm9\appxdiag.txt'
function W($m) { Add-Content -Path $o -Value $m -Encoding utf8 }
Remove-Item $o -ErrorAction SilentlyContinue
W ("== appxdiag " + (Get-Date))
W ("OS: " + (Get-CimInstance Win32_OperatingSystem).Version)
foreach ($f in 'Windows.UI.Xaml.dll','CoreMessaging.dll','Windows.UI.dll','twinapi.appcore.dll','Windows.UI.Xaml.Controls.dll','ntdll.dll','kernelbase.dll','appxdeploymentserver.dll','Windows.ApplicationModel.dll') {
  $p = "C:\Windows\System32\$f"
  if (Test-Path $p) { W ("{0,-34} {1}" -f $f, (Get-Item $p).VersionInfo.FileVersion) } else { W "$f missing" }
}
W "== crashes (Application log, last 30)"
Get-WinEvent -FilterHashtable @{LogName='Application'; Id=1000,1001,1026} -MaxEvents 30 -ErrorAction SilentlyContinue | ForEach-Object {
  $m = $_.Message -replace "`r?`n", ' | '
  W ("{0:HH:mm:ss} id={1} {2}" -f $_.TimeCreated, $_.Id, $m.Substring(0, [Math]::Min(600, $m.Length)))
}
W "== AppModel / Shell errors (last 40)"
foreach ($ln in 'Microsoft-Windows-AppModel-Runtime/Admin','Microsoft-Windows-AppXDeploymentServer/Operational','Microsoft-Windows-TWinUI/Operational','Microsoft-Windows-Shell-Core/Operational') {
  W "-- $ln"
  Get-WinEvent -LogName $ln -MaxEvents 40 -ErrorAction SilentlyContinue | Where-Object { $_.Level -le 3 } | Select-Object -First 15 | ForEach-Object {
    $m = $_.Message -replace "`r?`n", ' | '
    W ("{0:HH:mm:ss} id={1} {2}" -f $_.TimeCreated, $_.Id, $m.Substring(0, [Math]::Min(400, $m.Length)))
  }
}
W "== SystemApps on disk vs registered"
$reg = @{}
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | ForEach-Object { $reg[$_.InstallLocation] = $_ }
Get-ChildItem C:\Windows\SystemApps -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $mf = Join-Path $_.FullName 'AppxManifest.xml'
  $dv = ''
  if (Test-Path $mf) { try { $dv = ([xml](Get-Content $mf -Raw)).Package.Identity.Version } catch { $dv = 'xml?' } }
  $r = $reg[$_.FullName]
  W ("{0,-60} disk={1,-18} reg={2}" -f $_.Name, $dv, $(if ($r) { $r.Version + ' ' + $r.Status } else { 'NOT REGISTERED' }))
}
W "== registered packages whose InstallLocation is missing"
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.InstallLocation -and -not (Test-Path $_.InstallLocation) } | ForEach-Object { W ("{0} {1}" -f $_.PackageFullName, $_.InstallLocation) }
W "== framework packages (Xaml / VCLibs / WinUI)"
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'UI.Xaml|VCLibs|WindowsAppRuntime|NET.Native|WinUI' } | ForEach-Object { W ("{0} {1} {2}" -f $_.PackageFullName, $_.Status, $_.InstallLocation) }
W "== WER archive"
Get-ChildItem C:\ProgramData\Microsoft\Windows\WER\ReportArchive, C:\ProgramData\Microsoft\Windows\WER\ReportQueue -ErrorAction SilentlyContinue | Select-Object -First 25 | ForEach-Object { W $_.Name }
W "== done"
