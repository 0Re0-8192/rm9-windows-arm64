# build_vhdx_26100.ps1 - second Windows for the phone: Win11 25H2 (26100.5074, Pro) applied from the ISO into a dynamic VHDX (boot-from-VHD test, NEXT.md 0ca).
# Runs on the PC only (admin).  Output: <RM9_WORKDIR>\winboot\w26100\w26100.vhdx, log: build_vhdx_26100.log next to it.
$ErrorActionPreference = 'Stop'
$iso  = '<PROJECTS>\porta-a733-bringup\roms\Win11_25H2_Japanese_Arm64_v2.iso'
$dir  = '<RM9_WORKDIR>\winboot\w26100'
$vhdx = Join-Path $dir 'w26100.vhdx'
$log  = Join-Path $dir 'build_vhdx_26100.log'
New-Item -ItemType Directory -Force $dir | Out-Null
function Log($m) { $l = '{0} {1}' -f (Get-Date -Format 'HH:mm:ss'), $m; Add-Content -Path $log -Value $l; Write-Host $l }
if (Test-Path $vhdx) { throw "$vhdx exists" }
Log 'mount iso (read-only)'
$img = Mount-DiskImage -ImagePath $iso -StorageType ISO -Access ReadOnly -PassThru
$isoDrv = ($img | Get-Volume).DriveLetter
$wim = "${isoDrv}:\sources\install.wim"
Log "wim $wim"
try {
  $ds = @"
create vdisk file="$vhdx" maximum=49152 type=expandable
select vdisk file="$vhdx"
attach vdisk
create partition primary
format fs=ntfs quick label="W26100"
assign letter=V
"@
  $f = Join-Path $dir 'dp_create.txt'
  Set-Content -Path $f -Value $ds -Encoding ascii
  Log 'diskpart create'
  diskpart /s $f | Add-Content -Path $log
  if (-not (Test-Path 'V:\')) { throw 'V: not present' }
  Log 'dism apply-image (index 2 = Pro)'
  dism /Apply-Image /ImageFile:$wim /Index:2 /ApplyDir:V:\ | Add-Content -Path $log
  Log ('apply exit {0}' -f $LASTEXITCODE)
  if ($LASTEXITCODE -ne 0) { throw 'dism failed' }
  Log ('ntoskrnl: ' + (Get-Item V:\Windows\System32\ntoskrnl.exe).VersionInfo.FileVersion)
} finally {
  $ds2 = "select vdisk file=`"$vhdx`"`r`ndetach vdisk`r`n"
  $f2 = Join-Path $dir 'dp_detach.txt'
  Set-Content -Path $f2 -Value $ds2 -Encoding ascii
  diskpart /s $f2 | Add-Content -Path $log
  Dismount-DiskImage -ImagePath $iso | Out-Null
  Log 'detached, iso dismounted'
}
Log ('done, vhdx {0:N1} GiB' -f ((Get-Item $vhdx).Length / 1GB))
