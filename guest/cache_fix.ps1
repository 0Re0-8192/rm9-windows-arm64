# cache_fix.ps1 - the merged resource caches (C:\Windows\rescache\_merged) were built from the post-update package set; move them away (Windows rebuilds them) and unregister the packages the update added.
# log C:\rm9\cache_fix.txt
$log = 'C:\rm9\cache_fix.txt'
function L($m) { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) -Encoding utf8 }
foreach ($n in 'StartMenuExperienceHost','SearchHost','TextInputHost','ShellExperienceHost','SearchApp') { Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
$rc = 'C:\Windows\rescache'
if (Test-Path $rc) {
  L ("rescache: " + ((Get-ChildItem $rc -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object).Count) + ' files')
  & takeown.exe /F $rc /R /A /D Y 2>&1 | Out-Null
  & icacls.exe $rc /grant 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' /T /C /Q 2>&1 | Out-Null
  $dst = 'C:\rm9\rescache_bak'
  Remove-Item $dst -Recurse -Force -ErrorAction SilentlyContinue
  & robocopy.exe $rc $dst /E /B /MOVE /R:1 /W:1 /NFL /NDL /NJH /NJS /NP 2>&1 | Out-Null
  L ("after move: " + ((Get-ChildItem $rc -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object).Count) + ' files left; backup ' + ((Get-ChildItem $dst -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object).Count))
}
foreach ($p in 'MicrosoftWindows.61869836.InpApp','MicrosoftWindows.61869720.Voiess','MicrosoftWindows.61869721.Livtop','MicrosoftWindows.61869722.Speion') {
  $pk = Get-AppxPackage -AllUsers -Name $p -ErrorAction SilentlyContinue
  if (-not $pk) { L "not registered: $p"; continue }
  foreach ($x in $pk) { try { Remove-AppxPackage -Package $x.PackageFullName -AllUsers -ErrorAction Stop; L "removed $($x.PackageFullName)" } catch { L "remove FAILED $($x.PackageFullName): $($_.Exception.Message -replace "`r?`n",' ')" } }
}
L 'done'
