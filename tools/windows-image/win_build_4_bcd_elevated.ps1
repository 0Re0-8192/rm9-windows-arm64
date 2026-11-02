$ErrorActionPreference='Stop'
$sp="C:\Users\<user>\AppData\Local\Temp\claude\C--Users-<user>-Documents-projects\fcf1cceb-daf5-429b-9ea5-de2734fb71b2\scratchpad"
$out="<RM9_WORKDIR>\winboot"
$vhd="$sp\bcdgen3.vhd"
$st="$out\BCD_raw"
Start-Transcript "$out\bcdgen3_log.txt" -Force | Out-Null
try {
  "create vdisk file=`"$vhd`" maximum=1024 type=expandable`r`nattach vdisk" | Set-Content "$sp\dp1.txt" -Encoding ascii
  diskpart /s "$sp\dp1.txt"
  $disk = Get-Disk | Where-Object { $_.Location -like '*bcdgen3.vhd*' }
  if (-not $disk) { throw "vhd disk not found" }
  Initialize-Disk -Number $disk.Number -PartitionStyle GPT
  $esp = New-Partition -DiskNumber $disk.Number -Size 200MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -AssignDriveLetter
  $win = New-Partition -DiskNumber $disk.Number -UseMaximumSize -GptType '{ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}' -AssignDriveLetter
  Format-Volume -Partition $esp -FileSystem FAT32 -NewFileSystemLabel ESP -Confirm:$false | Out-Null
  Format-Volume -Partition $win -FileSystem NTFS -NewFileSystemLabel Windows -Confirm:$false | Out-Null
  $e = ($esp | Get-Partition).DriveLetter; $w = ($win | Get-Partition).DriveLetter
  $info = [ordered]@{ disk=(Get-Disk -Number $disk.Number).Guid; esp=($esp | Get-Partition).Guid; win=($win | Get-Partition).Guid; espLetter="$e"; winLetter="$w" }
  $info | ConvertTo-Json | Set-Content "$out\bcd_vhd_guids.json" -Encoding ascii
  $info | Format-List

  bcdedit /createstore $st
  bcdedit /store $st /create '{bootmgr}' /d "Windows Boot Manager"
  bcdedit /store $st /set '{bootmgr}' device "partition=${e}:"
  bcdedit /store $st /set '{bootmgr}' path '\EFI\Microsoft\Boot\bootmgfw.efi'
  bcdedit /store $st /set '{bootmgr}' locale en-US
  bcdedit /store $st /set '{bootmgr}' timeout 3
  $o = bcdedit /store $st /create /d "Windows 11 ARM64" /application osloader
  $o
  $g = [regex]::Match(($o -join ' '), '\{[0-9a-fA-F-]{36}\}').Value
  "LOADER=$g"
  bcdedit /store $st /set $g device "partition=${w}:"
  bcdedit /store $st /set $g osdevice "partition=${w}:"
  bcdedit /store $st /set $g path '\Windows\system32\winload.efi'
  bcdedit /store $st /set $g systemroot '\Windows'
  bcdedit /store $st /set $g locale en-US
  bcdedit /store $st /set $g nx OptIn
  bcdedit /store $st /set $g bootmenupolicy Standard
  bcdedit /store $st /set '{bootmgr}' default $g
  bcdedit /store $st /displayorder $g /addfirst
  bcdedit /store $st /enum all
} catch { "ERROR: $_" }
finally {
  "select vdisk file=`"$vhd`"`r`ndetach vdisk" | Set-Content "$sp\dp2.txt" -Encoding ascii
  diskpart /s "$sp\dp2.txt"
  Stop-Transcript | Out-Null
}
