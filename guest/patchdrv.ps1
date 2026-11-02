# patchdrv.ps1 - swap the Wi-Fi driver binary for the polling build (S:\rm9\qcwlan_patched.sys) before qcwlan is started; the original is kept once as C:\rm9\qcwlan_orig.sys
# `patchdrv.ps1 -Restore` puts the original back.   Log: S:\rm9\patchdrv.txt
param([switch]$Restore)
$o = 'S:\rm9\patchdrv.txt'
function W($m) { ("$(Get-Date -Format 'HH:mm:ss.fff') $m") | Out-File -Append -Encoding ascii $o }
# the first version of this script dropped a stray copy here
Remove-Item 'C:\Windows\System32\drivers\qcwlanhmt8380.sys' -Force -ErrorAction SilentlyContinue
$img = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\qcwlan' -ErrorAction SilentlyContinue).ImagePath
W ('qcwlan ImagePath = ' + $img)
$path = $img
if ($path -match '^\\SystemRoot\\') { $path = 'C:\Windows\' + $path.Substring(12) }
elseif ($path -match '^System32\\') { $path = 'C:\Windows\' + $path }
elseif ($path -match '^\\\?\?\\') { $path = $path.Substring(4) }
W ('resolved = ' + $path + ' exists=' + (Test-Path -LiteralPath $path))
if (-not (Test-Path -LiteralPath $path)) {
    $dir = Split-Path $path
    W ('dir exists=' + (Test-Path -LiteralPath $dir))
    Get-ChildItem 'C:\Windows\System32\DriverStore\FileRepository' -Filter 'qcwlan*' -ErrorAction SilentlyContinue | ForEach-Object { W ('  store: ' + $_.FullName) ; Get-ChildItem $_.FullName -ErrorAction SilentlyContinue | ForEach-Object { W ('    ' + $_.Name + ' ' + $_.Length) } }
    W 'cannot find the driver binary: nothing done'
    return
}
if (-not (Test-Path 'C:\rm9\qcwlan_orig.sys')) { Copy-Item -LiteralPath $path 'C:\rm9\qcwlan_orig.sys' -Force; W ('original saved to C:\rm9\qcwlan_orig.sys size ' + (Get-Item 'C:\rm9\qcwlan_orig.sys').Length) }
$src = if ($Restore) { 'C:\rm9\qcwlan_orig.sys' } else { 'S:\rm9\qcwlan_patched.sys' }
if (-not (Test-Path $src)) { W ('no source ' + $src + ': nothing done'); return }
takeown /f $path 2>&1 | ForEach-Object { W ('  ' + $_) }
icacls $path /grant 'Administrators:F' 2>&1 | ForEach-Object { W ('  ' + $_) }
Copy-Item -LiteralPath $src $path -Force
W ('copied ' + $src + ' -> ' + $path + ' size ' + (Get-Item -LiteralPath $path).Length)
W ('signature: ' + (Get-AuthenticodeSignature -LiteralPath $path).Status)
