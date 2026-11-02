# dumpsetup.ps1 - WER LocalDumps (full dump) for the shell hosts -> C:\rm9\dumps
New-Item -ItemType Directory -Force C:\rm9\dumps | Out-Null
foreach ($e in 'SearchHost.exe','StartMenuExperienceHost.exe','TextInputHost.exe') {
  $k = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps\$e"
  New-Item -Path $k -Force | Out-Null
  New-ItemProperty -Path $k -Name DumpFolder -Value 'C:\rm9\dumps' -PropertyType ExpandString -Force | Out-Null
  New-ItemProperty -Path $k -Name DumpType -Value 2 -PropertyType DWord -Force | Out-Null
  New-ItemProperty -Path $k -Name DumpCount -Value 3 -PropertyType DWord -Force | Out-Null
}
'ok'
