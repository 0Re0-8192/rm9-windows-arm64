# cfg_vhdx_26100.ps1 - copy the pristine w26100.vhdx and add the files that let Windows Setup finish unattended on the phone and install the rm9diag boot service.
# File additions only (the Setup registry state stays untouched - skipping Setup crashes LSASS, see HANDOVER).  Runs on the PC (admin).  Output: winboot\w26100\w26100_cfg.vhdx
$ErrorActionPreference = 'Stop'
$dir = '<RM9_WORKDIR>\winboot\w26100'
$src = Join-Path $dir 'w26100.vhdx'
$dst = Join-Path $dir 'w26100_cfg.vhdx'
$wp  = '<RM9_WORKDIR>\refs\winpe'
$log = Join-Path $dir 'cfg_vhdx.log'
function Log($m) { $l = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $m; Add-Content -Path $log -Value $l; Write-Host $l }
function Crlf($from, $to) {
  $t = [IO.File]::ReadAllText($from) -replace "`r`n", "`n"
  $t = $t -replace "`n", "`r`n"
  [IO.File]::WriteAllText($to, $t, (New-Object Text.UTF8Encoding($false)))
}
if (Test-Path $dst) { throw "$dst exists" }
Log 'copy pristine vhdx'
Copy-Item $src $dst
$ds = "select vdisk file=`"$dst`"`r`nattach vdisk`r`nselect partition 1`r`nassign letter=W`r`n"
Set-Content -Path (Join-Path $dir 'dp_cfg_attach.txt') -Value $ds -Encoding ascii
try {
  diskpart /s (Join-Path $dir 'dp_cfg_attach.txt') | Add-Content -Path $log
  if (-not (Test-Path 'W:\Windows\System32\ntoskrnl.exe')) { throw 'W: has no Windows' }
  Log ('ntoskrnl ' + (Get-Item W:\Windows\System32\ntoskrnl.exe).VersionInfo.FileVersion)
  foreach ($d in 'W:\rm9', 'W:\Windows\Panther\Unattend', 'W:\Windows\Setup\Scripts') { New-Item -ItemType Directory -Force $d | Out-Null }
  Crlf "$wp\rm9_diag_boot.cmd" 'W:\rm9\diag.cmd'
  Crlf "$wp\firstlogon_26100.cmd" 'W:\rm9\firstlogon.cmd'
  Crlf "$wp\setupcomplete_26100.cmd" 'W:\Windows\Setup\Scripts\SetupComplete.cmd'
  foreach ($t in 'W:\Windows\Panther\Unattend\Unattend.xml', 'W:\Windows\Panther\unattend.xml', 'W:\Unattend.xml') { Copy-Item "$wp\unattend_rm9.xml" $t -Force }
  Log 'files added'
  Get-ChildItem W:\rm9, W:\Windows\Setup\Scripts, W:\Windows\Panther\Unattend | ForEach-Object { Log ('  ' + $_.FullName + ' ' + $_.Length) }
} finally {
  $ds2 = "select vdisk file=`"$dst`"`r`ndetach vdisk`r`n"
  Set-Content -Path (Join-Path $dir 'dp_cfg_detach.txt') -Value $ds2 -Encoding ascii
  diskpart /s (Join-Path $dir 'dp_cfg_detach.txt') | Add-Content -Path $log
  Log 'detached'
}
Log ('done {0:N0} bytes' -f (Get-Item $dst).Length)
