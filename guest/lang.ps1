# lang.ps1 - language / locale state (MRM falls over when the UI language has no resources).  Output C:\rm9\lang.txt
$o = 'C:\rm9\lang.txt'; Remove-Item $o -ErrorAction SilentlyContinue
function W($m) { Add-Content -Path $o -Value $m -Encoding utf8 }
W ("SystemLocale: " + (Get-WinSystemLocale).Name)
W ("UILanguageOverride: " + (Get-WinUILanguageOverride).LanguageTag)
W ("DefaultInputMethod: " + (Get-WinDefaultInputMethodOverride))
W ("Culture(SYSTEM): " + (Get-Culture).Name + " UI: " + (Get-UICulture).Name)
W "-- MUI"
foreach ($k in 'HKLM:\SYSTEM\CurrentControlSet\Control\MUI\UILanguages','HKLM:\SYSTEM\CurrentControlSet\Control\Nls\Language','HKLM:\SYSTEM\CurrentControlSet\Control\MUI\Settings') {
  W $k
  Get-ChildItem $k -ErrorAction SilentlyContinue | ForEach-Object { W ("  sub " + $_.PSChildName) }
  Get-ItemProperty $k -ErrorAction SilentlyContinue | Out-String | ForEach-Object { W $_ }
}
W "-- Default user / .DEFAULT / rm9 user language keys"
foreach ($hive in 'HKU:\.DEFAULT','HKU:\S-1-5-18') { }
New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS -ErrorAction SilentlyContinue | Out-Null
Get-ChildItem HKU:\ -ErrorAction SilentlyContinue | ForEach-Object {
  $s = $_.PSChildName
  if ($s -match '_Classes$') { return }
  W ("hive $s")
  foreach ($p in "HKU:\$s\Control Panel\Desktop", "HKU:\$s\Control Panel\International", "HKU:\$s\Control Panel\International\User Profile") {
    $v = Get-ItemProperty $p -ErrorAction SilentlyContinue
    if ($v) { W ("  $p"); ($v | Select-Object PreferredUILanguages, PreferredUILanguagesPending, MultiUILanguageId, Locale, LocaleName, Languages | Out-String) -split "`n" | ForEach-Object { if ($_.Trim()) { W ("    " + $_.TrimEnd()) } } }
  }
}
W "-- installed language packs (dism-free): C:\Windows\System32\<lang> folders"
Get-ChildItem C:\Windows\System32 -Directory | Where-Object { $_.Name -match '^[a-z]{2}-[A-Z]{2}$' } | ForEach-Object { W ("  " + $_.Name) }
W "-- SystemApps pris languages (CBS)"
Get-ChildItem 'C:\Windows\SystemApps\MicrosoftWindows.Client.Core_cw5n1h2txyewy' -Filter 'resources*.pri' -Recurse | Select-Object -First 10 | ForEach-Object { W ("  " + $_.FullName.Substring(26)) }
