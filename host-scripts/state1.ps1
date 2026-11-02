$o = 'C:\rm9\state1.txt'
(cmd /c ver) | Out-File $o -Encoding utf8
'--- wlan' | Out-File $o -Append -Encoding utf8
(netsh wlan show interfaces) | Out-File $o -Append -Encoding utf8
'--- ip' | Out-File $o -Append -Encoding utf8
(ipconfig) | Out-File $o -Append -Encoding utf8
'--- problem devices' | Out-File $o -Append -Encoding utf8
Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne 'OK' -and $_.Class -ne 'Volume' } | ForEach-Object { $_.Class + ' | ' + $_.FriendlyName + ' | ' + $_.Status + ' | ' + $_.InstanceId } | Out-File $o -Append -Encoding utf8
'--- wifi_rpfix' | Out-File $o -Append -Encoding utf8
Get-Content S:\rm9\wifi_rpfix.txt -ErrorAction SilentlyContinue | Select-Object -Last 8 | Out-File $o -Append -Encoding utf8
'--- display timeout' | Out-File $o -Append -Encoding utf8
(powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOIDLE) | Out-File $o -Append -Encoding utf8
