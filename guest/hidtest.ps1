# S:\rm9\hidtest.ps1 (SYSTEM, started by esp_run_hidtest.cmd about 90 s after boot) - try the virtual HID touch screen instead of the InjectTouchInput injector.
#   1. stop the injector supervisor (this boot only; it is an onstart task, so the next boot is back to normal) and kill the running touchinject.ps1
#   2. install rm9hid (ROOT\RM9HID + rm9hid.inf) from S:\rm9\hidpkg\ via hidinstall.ps1
#   3. run touchhid.ps1 (feeds the HID device from C:\Users\Public\rm9shot\touch.cur, which the rm9touchpoll task writes) for the rest of the 10-minute run
# Log: S:\rm9\hidtest.txt (WriteThrough).  Copies of C:\rm9\hid\install.log and C:\rm9\link\touchhid.txt go to S:\rm9\ at the end.
$fs = New-Object IO.FileStream('S:\rm9\hidtest.txt', [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
function L($s) { $b = [Text.Encoding]::ASCII.GetBytes(((Get-Date -Format 'HH:mm:ss.fff') + ' ' + $s + "`r`n")); $fs.Write($b, 0, $b.Length); $fs.Flush() }
L '=== hidtest start'
# driver installation was switched off after the Windows Update accident (notes: set it to 0 for the HID install)
$k = 'HKLM:\SYSTEM\CurrentControlSet\Services\DeviceInstall\Parameters'
try { L ('DeviceInstallDisabled=' + (Get-ItemProperty $k -Name DeviceInstallDisabled -ErrorAction SilentlyContinue).DeviceInstallDisabled); Set-ItemProperty $k -Name DeviceInstallDisabled -Value 0 -Type DWord -ErrorAction Stop } catch { L ('DeviceInstallDisabled: ' + $_.Exception.Message) }
L ('schtasks end rm9touchsup: ' + ((& schtasks /end /tn rm9touchsup 2>&1) -join ' '))
foreach ($p in (Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*touchinject.ps1*' })) { L ('kill injector pid ' + $p.ProcessId); Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
L ('touchpoll running: ' + [bool](Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*touchpoll.ps1*' }))
New-Item -ItemType Directory -Force C:\rm9\hid | Out-Null
foreach ($f in 'rm9hid.sys', 'rm9hid.inf', 'rm9hid.cat') { Copy-Item "S:\rm9\hidpkg\$f" "C:\rm9\hid\$f" -Force; L ("copied $f " + (Get-Item "C:\rm9\hid\$f").Length) }
Copy-Item S:\rm9\hidinstall.ps1 C:\rm9\link\hidinstall.ps1 -Force
Copy-Item S:\rm9\touchhid.ps1 C:\rm9\link\touchhid.ps1 -Force
Remove-Item C:\rm9\hid\install.log -ErrorAction SilentlyContinue
try { & powershell -NoProfile -ExecutionPolicy Bypass -File C:\rm9\link\hidinstall.ps1 *> C:\rm9\hid\install_out.txt } catch { L ('hidinstall threw: ' + $_.Exception.Message) }
L 'hidinstall done'
Get-Content C:\rm9\hid\install.log -ErrorAction SilentlyContinue | ForEach-Object { L ('install.log: ' + $_) }
foreach ($d in (Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -like '*RM9*' -or $_.InstanceId -like 'HID\VHF*' })) { L ('pnp: ' + $d.Class + ' | ' + $d.FriendlyName + ' | ' + $d.Status + ' | ' + $d.InstanceId) }
L ('rm9hid service: ' + ((& sc.exe query rm9hid 2>&1) -join ' '))
Remove-Item C:\rm9\link\touchhid.txt -ErrorAction SilentlyContinue
$proc = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\rm9\link\touchhid.ps1', '-Seconds', '480' -PassThru -WindowStyle Hidden
L ('touchhid started pid ' + $proc.Id + ' (480 s) - TOUCH THE SCREEN NOW')
for ($i = 0; $i -lt 48; $i++) {
    Start-Sleep 10
    $cur = ''
    try { $cur = [IO.File]::ReadAllText('C:\Users\Public\rm9shot\touch.cur').Trim() } catch {}
    L ('alive=' + (-not $proc.HasExited) + ' touch.cur=' + $cur)
    Copy-Item C:\rm9\link\touchhid.txt S:\rm9\touchhid.txt -Force -ErrorAction SilentlyContinue
}
L '=== hidtest end'
$fs.Close()
