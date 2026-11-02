@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File S:\rm9\launch_in_session.ps1 "explorer.exe ms-settings:windowsupdate" > C:\rm9\settings1.txt 2>&1
ping -n 30 127.0.0.1 >nul
tasklist /fi "imagename eq SystemSettings.exe" >> C:\rm9\settings1.txt 2>&1
wevtutil qe Application /c:5 /rd:true /q:"*[System[Provider[@Name='Application Error'] and TimeCreated[timediff(@SystemTime) <= 120000]]]" /f:text >> C:\rm9\settings1.txt 2>&1
