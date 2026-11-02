foreach ($e in 'SearchHost.exe','StartMenuExperienceHost.exe','TextInputHost.exe') { Remove-Item "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\$e" -Force -ErrorAction SilentlyContinue }
Remove-Item C:\rm9\dumps -Recurse -Force -ErrorAction SilentlyContinue
'dumps off'
