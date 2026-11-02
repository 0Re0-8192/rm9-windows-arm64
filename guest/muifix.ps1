# muifix.ps1 - replace the mismatched System32\en-US .mui files with the GA copies listed in C:\rm9\mui_fix.txt ("dest|src"); originals to C:\rm9\mui_bak.  log C:\rm9\muifix.txt
$log = 'C:\rm9\muifix.txt'
function L($m) { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) -Encoding utf8 }
foreach ($n in 'StartMenuExperienceHost','SearchHost','TextInputHost','ShellExperienceHost') { Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force C:\rm9\mui_bak | Out-Null
foreach ($l in Get-Content C:\rm9\mui_fix.txt -Encoding utf8) {
  if (-not $l) { continue }
  $d, $s = $l -split '\|', 2
  Copy-Item -LiteralPath $d -Destination ("C:\rm9\mui_bak\" + (Split-Path $d -Leaf)) -Force -ErrorAction SilentlyContinue
  & takeown.exe /F $d /A 2>&1 | Out-Null
  & icacls.exe $d /grant 'SYSTEM:F' 'Administrators:F' 2>&1 | Out-Null
  try { Copy-Item -LiteralPath $s -Destination $d -Force -ErrorAction Stop; L "replaced $d" } catch {
    try { Move-Item -LiteralPath $d -Destination ($d + '.old') -Force -ErrorAction Stop; Copy-Item -LiteralPath $s -Destination $d -Force -ErrorAction Stop; L "replaced (via rename) $d" } catch { L "FAILED $d : $($_.Exception.Message)" }
  }
}
L 'done'
