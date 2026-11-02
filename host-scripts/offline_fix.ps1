# runs inside the 28000 Windows (SYSTEM): attach C:\w26100.vhdx with diskpart, inspect/repair the 26100 SYSTEM hive (qcwlan must not load), copy logs out, detach
$o = 'C:\rm9\offline_fix.txt'
function W($m) { ("$(Get-Date -Format 'HH:mm:ss') $m") | Out-File -Append -Encoding utf8 $o }
Remove-Item $o -ErrorAction SilentlyContinue
$img = 'C:\w26100.vhdx'
W ('image exists=' + (Test-Path $img) + ' size=' + (Get-Item $img -ErrorAction SilentlyContinue).Length)
Set-Content 'C:\rm9\dp_attach.txt' -Encoding ascii @("select vdisk file=$img", 'attach vdisk')
diskpart /s 'C:\rm9\dp_attach.txt' 2>&1 | ForEach-Object { W ('dp: ' + $_) }
Set-Content 'C:\rm9\dp_detail.txt' -Encoding ascii @("select vdisk file=$img", 'detail vdisk')
$det = diskpart /s 'C:\rm9\dp_detail.txt' 2>&1
$m = ($det | Select-String 'Associated disk#:\s*(\d+)')
if (-not $m) { W 'no associated disk number'; return }
$dn = [int]$m.Matches[0].Groups[1].Value
W ('disk number ' + $dn)
# SanPolicy=4 keeps a newly attached disk offline: bring it online (the volume then mounts by itself after a few seconds)
Set-Content 'C:\rm9\dp_online.txt' -Encoding ascii @("select disk $dn", 'attributes disk clear readonly', 'online disk')
diskpart /s 'C:\rm9\dp_online.txt' 2>&1 | ForEach-Object { W ('dp: ' + $_) }
$drv = $null
for ($i = 0; $i -lt 30 -and -not $drv; $i++) {
  $drv = (Get-Partition -DiskNumber $dn -ErrorAction SilentlyContinue | Where-Object { $_.DriveLetter } | Select-Object -First 1).DriveLetter
  if (-not $drv) { Start-Sleep 2 }
}
W ('drive letter = ' + $drv)
if (-not $drv) { return }
$root = $drv + ':\'
$hive = $root + 'Windows\System32\config\SYSTEM'
W ('hive exists=' + (Test-Path $hive))
reg load HKLM\W26SYS $hive 2>&1 | ForEach-Object { W ('reg load: ' + $_) }
$cur = (Get-ItemProperty 'HKLM:\W26SYS\Select').Current
W ('Select.Current=' + $cur)
foreach ($cs in 'ControlSet001','ControlSet002') {
  $k = "HKLM:\W26SYS\$cs\Services\qcwlan"
  if (Test-Path $k) {
    $p = Get-ItemProperty $k
    W ("$cs qcwlan Start=" + $p.Start + " ImagePath=" + $p.ImagePath)
    Set-ItemProperty $k -Name Start -Value 4 -Type DWord
    W ("$cs qcwlan Start set to " + (Get-ItemProperty $k).Start)
  } else { W "$cs qcwlan service key absent" }
}
reg query 'HKLM\W26SYS\ControlSet001\Enum\PCI\VEN_17CB&DEV_1107&SUBSYS_110717CB&REV_01' /s 2>&1 | Select-Object -First 25 | ForEach-Object { W ('  ' + $_) }
[gc]::Collect(); Start-Sleep 1
reg unload HKLM\W26SYS 2>&1 | ForEach-Object { W ('reg unload: ' + $_) }
New-Item -ItemType Directory -Force C:\rm9\w26100_logs | Out-Null
Copy-Item ($root + 'rm9\*.txt') C:\rm9\w26100_logs -Force -ErrorAction SilentlyContinue
Copy-Item ($root + 'Windows\System32\winevt\Logs\System.evtx') C:\rm9\w26100_logs -Force -ErrorAction SilentlyContinue
Get-ChildItem ($root + 'Windows\Minidump') -ErrorAction SilentlyContinue | ForEach-Object { W ('minidump ' + $_.Name + ' ' + $_.Length); Copy-Item $_.FullName C:\rm9\w26100_logs -Force }
if (Test-Path ($root + 'Windows\MEMORY.DMP')) { W 'MEMORY.DMP present' }
Get-ChildItem ($root + 'Windows\System32\drivers') -Filter 'qcwlan*' -ErrorAction SilentlyContinue | ForEach-Object { W ('drivers: ' + $_.Name + ' ' + $_.Length) }
Set-Content 'C:\rm9\dp_detach.txt' -Encoding ascii @("select vdisk file=$img", 'detach vdisk')
diskpart /s 'C:\rm9\dp_detach.txt' 2>&1 | ForEach-Object { W ('dp: ' + $_) }
W 'detached; done'
