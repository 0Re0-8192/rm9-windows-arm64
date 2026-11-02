# apps_apply.ps1 - put C:\Windows\SystemApps back to the original (UUP 28000.x base) content.
#   inputs (C:\rm9\link): apps_ga_patch.tar (changed + missing original files), restore_list.txt, del_extra.txt (live-only files of the Client.* packages; relative to SystemApps, backslashes)
#   -Phase test : only check that overwrite / delete work on one file each (no change)
#   -Phase apply: back up everything that is replaced or removed to C:\rm9\apps_bak, extract the patch to C:\rm9\apps_stage, copy it over, remove the extras
#   -Phase reg  : re-register the touched packages
# log: C:\rm9\apps_apply.txt
param([string]$Phase = 'test')
$ErrorActionPreference = 'Continue'
$log = 'C:\rm9\apps_apply.txt'
function L($m) { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) -Encoding utf8 }
$apps = 'C:\Windows\SystemApps'
$in = 'C:\rm9\link'
$bak = 'C:\rm9\apps_bak'
$stage = 'C:\rm9\apps_stage'
L "== phase $Phase"
function Unlock($p) {
  & takeown.exe /F $p /A 2>&1 | Out-Null
  & icacls.exe $p /grant 'SYSTEM:F' 'Administrators:F' 2>&1 | Out-Null
}
function KillHosts {
  foreach ($n in 'StartMenuExperienceHost','SearchHost','TextInputHost','ShellExperienceHost','LockApp','SearchApp') { Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
}
if ($Phase -eq 'test') {
  $del = Get-Content "$in\del_extra.txt" -Encoding utf8 | Where-Object { $_ } | Select-Object -First 1
  $f = Join-Path $apps $del
  L "test delete target: $f exists=$(Test-Path $f)"
  try { $fs = [IO.File]::Open($f, 'Open', 'ReadWrite', 'None'); $fs.Dispose(); L 'open for write: OK' } catch { L "open for write FAILED: $($_.Exception.Message)"; Unlock $f; try { $fs = [IO.File]::Open($f, 'Open', 'ReadWrite', 'None'); $fs.Dispose(); L 'open for write after unlock: OK' } catch { L "still FAILED: $($_.Exception.Message)" } }
  $ch = Get-Content "$in\restore_list.txt" -Encoding utf8 | Where-Object { $_ -match 'MicrosoftWindows.Client.Core_' } | Select-Object -First 1
  $g = Join-Path $apps ($ch -replace '/', '\')
  L "test overwrite target: $g exists=$(Test-Path $g)"
  if (Test-Path $g) { try { $fs = [IO.File]::Open($g, 'Open', 'ReadWrite', 'None'); $fs.Dispose(); L 'open for write: OK' } catch { L "open for write FAILED: $($_.Exception.Message)" } }
  L 'tar: ' + (& tar.exe --version 2>&1 | Select-Object -First 1)
  return
}
if ($Phase -eq 'apply') {
  KillHosts
  L 'killed shell hosts'
  # 1. backup of what will change
  $rest = Get-Content "$in\restore_list.txt" -Encoding utf8 | Where-Object { $_ }
  $del = Get-Content "$in\del_extra.txt" -Encoding utf8 | Where-Object { $_ }
  $nb = 0
  foreach ($r in $rest) {
    $rel = $r -replace '/', '\'
    $s = Join-Path $apps $rel
    if (Test-Path -LiteralPath $s) { $d = Join-Path "$bak\changed" $rel; New-Item -ItemType Directory -Force -Path (Split-Path $d) | Out-Null; Copy-Item -LiteralPath $s -Destination $d -Force -ErrorAction SilentlyContinue; $nb++ }
  }
  L "backed up $nb changed files"
  $nd = 0
  foreach ($rel in $del) {
    $s = Join-Path $apps $rel
    if (Test-Path -LiteralPath $s) { $d = Join-Path "$bak\extra" $rel; New-Item -ItemType Directory -Force -Path (Split-Path $d) | Out-Null; Copy-Item -LiteralPath $s -Destination $d -Force -ErrorAction SilentlyContinue; $nd++ }
  }
  L "backed up $nd extra files"
  # 2. extract the patch and copy it over
  Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $stage | Out-Null
  & tar.exe -xf "$in\apps_ga_patch.tar" -C $stage 2>&1 | ForEach-Object { L "tar: $_" }
  $cnt = (Get-ChildItem $stage -Recurse -File | Measure-Object).Count
  L "staged $cnt files"
  $rc = & robocopy.exe $stage $apps /E /B /IS /IT /R:2 /W:1 /NFL /NDL /NJH /NP 2>&1 | Out-String
  L ("robocopy exit $LASTEXITCODE`n" + $rc.Substring([Math]::Max(0, $rc.Length - 700)))
  # 3. remove the extras
  $fail = 0; $done = 0
  foreach ($rel in $del) {
    $f = Join-Path $apps $rel
    if (-not (Test-Path -LiteralPath $f)) { continue }
    try { [IO.File]::Delete($f); $done++ } catch {
      Unlock $f
      try { [IO.File]::Delete($f); $done++ } catch { $fail++; L "delete FAILED $rel : $($_.Exception.Message)" }
    }
  }
  L "removed $done extras, failed $fail"
  # empty directories left behind
  Get-ChildItem $apps -Directory -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending | Where-Object { -not (Get-ChildItem $_.FullName -Force -ErrorAction SilentlyContinue) } | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
  L 'apply done'
  return
}
if ($Phase -eq 'reg') {
  KillHosts
  foreach ($p in 'MicrosoftWindows.Client.CBS_cw5n1h2txyewy','MicrosoftWindows.Client.Core_cw5n1h2txyewy','MicrosoftWindows.Client.CoreAI_cw5n1h2txyewy','MicrosoftWindows.Client.Photon_cw5n1h2txyewy','MicrosoftWindows.Client.FileExp_cw5n1h2txyewy','MicrosoftWindows.Client.OOBE_cw5n1h2txyewy') {
    $m = Join-Path $apps "$p\appxmanifest.xml"
    if (-not (Test-Path $m)) { $m = Join-Path $apps "$p\AppxManifest.xml" }
    try { Add-AppxPackage -Register $m -DisableDevelopmentMode -ErrorAction Stop; L "registered $p" } catch { L "register FAILED $p : $($_.Exception.Message -replace "`r?`n",' ')" }
  }
  L 'reg done'
}
