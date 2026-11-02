param([Parameter(Mandatory=$true)][string]$Local, [string]$Remote = 'rm9/run.cmd', [switch]$Binary)
# Put a file onto the phone's ESP (FAT) from Android (root): mounts /dev/block/by-name/esp, copies, syncs, unmounts.
# Windows reads it as S:\<Remote> (mountvol S: /S).  Line endings are converted to CRLF for .cmd files.
$adb = 'C:\ADB\adb.exe'
if (-not $env:ANDROID_SERIAL) { $env:ANDROID_SERIAL = '<PHONE_SERIAL>' }  # new PC: pin the target when a second adb device is attached
$tmp = Join-Path $env:TEMP 'esp_put_payload'
if ($Binary) { Copy-Item -LiteralPath $Local -Destination $tmp -Force } else {
$text = [IO.File]::ReadAllText($Local) -replace "`r`n","`n" -replace "`n","`r`n"
[IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding($false)))
}
& $adb push $tmp /data/local/tmp/esp_put_payload | Out-Null
$dir = ($Remote -replace '/[^/]*$','')
$sh = @"
M=/data/local/tmp/espm
mkdir -p `$M
umount `$M 2>/dev/null
mount -t vfat -o rw,umask=000 /dev/block/by-name/esp `$M || { echo MOUNT_FAILED; exit 1; }
mkdir -p `$M/$dir
cp /data/local/tmp/esp_put_payload `$M/$Remote
sync
ls -la `$M/$dir
umount `$M
rm -f /data/local/tmp/esp_put_payload
echo OK
"@
Set-Content "$env:TEMP\esp_put.sh" ($sh -replace "`r","") -Encoding ascii -NoNewline
& $adb push "$env:TEMP\esp_put.sh" /data/local/tmp/esp_put.sh | Out-Null
& $adb shell "su -c 'sh /data/local/tmp/esp_put.sh'"
