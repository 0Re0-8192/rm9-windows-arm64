# muirevert.ps1 - put back the originals (C:\rm9\mui_bak) of the System32\en-US .mui files except windows.ui.xaml.dll.mui (the one that fixed the Start host).  log C:\rm9\muirevert.txt
$log = 'C:\rm9\muirevert.txt'
function L($m) { Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) -Encoding utf8 }
foreach ($n in 'StartMenuExperienceHost','SearchHost','TextInputHost','ShellExperienceHost') { Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
foreach ($f in Get-ChildItem C:\rm9\mui_bak -File) {
  if ($f.Name -ieq 'windows.ui.xaml.dll.mui') { L "keep GA copy: $($f.Name)"; continue }
  $d = "C:\Windows\System32\en-US\$($f.Name)"
  try { Copy-Item -LiteralPath $f.FullName -Destination $d -Force -ErrorAction Stop; L "reverted $d" } catch { L "FAILED $d : $($_.Exception.Message)" }
}
L 'done'
