$log = "$env:TEMP\usbreset.log"
"=== restart failed usb device ===" | Out-File $log -Encoding utf8
pnputil /restart-device "USB\VID_0000&PID_0002\6&5280D8E&0&1" *>> $log
Start-Sleep -Seconds 3
pnputil /scan-devices *>> $log
"=== done ===" | Out-File $log -Append -Encoding utf8
