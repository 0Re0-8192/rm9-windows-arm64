# setlang.ps1 - run in the console user's session: the user language list was only {ja}, but the OS has only the en-US UI resources -> MRM finds no default candidate (0x80073B01) in the shell hosts.
$l = New-WinUserLanguageList en-US
Set-WinUserLanguageList $l -Force
Add-Content C:\rm9\setlang.txt ((Get-Date -Format 'HH:mm:ss') + ' list now: ' + ((Get-WinUserLanguageList | ForEach-Object { $_.LanguageTag }) -join ','))
