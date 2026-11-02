@echo off
ver > C:\rm9\state1.txt
netsh wlan show interfaces >> C:\rm9\state1.txt 2>&1
ipconfig | findstr /i "IPv4 Wi-Fi 接続" >> C:\rm9\state1.txt 2>&1
powershell -NoProfile -Command "Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne 'OK' -and $_.Class -ne 'Volume' } | Select-Object Class,FriendlyName,Status,InstanceId | Format-Table -AutoSize | Out-String -Width 200" >> C:\rm9\state1.txt 2>&1
powershell -NoProfile -Command "Get-Content C:\rm9\wifi_rpfix.txt -ErrorAction SilentlyContinue | Select-Object -Last 5; Get-Content S:\rm9\wifi_rpfix.txt -ErrorAction SilentlyContinue | Select-Object -Last 8" >> C:\rm9\state1.txt 2>&1
powercfg /q SCHEME_CURRENT SUB_VIDEO VIDEOIDLE >> C:\rm9\state1.txt 2>&1
