$log = "$env:TEMP\usbrebind.log"
"=== remove failed device ===" | Out-File $log -Encoding utf8
pnputil /remove-device "USB\VID_0000&PID_0002\6&5280D8E&0&1" *>> $log
Start-Sleep -Seconds 2
"=== scan ===" | Out-File $log -Append -Encoding utf8
pnputil /scan-devices *>> $log
Start-Sleep -Seconds 4
"=== done ===" | Out-File $log -Append -Encoding utf8
