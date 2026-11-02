# aclfix.ps1 - reset the DACL (inherit from the parent) of every path in the given list, after saving the old SDDL.  list: lines of full paths (trailing \ = directory).
#   aclfix.ps1 -List C:\rm9\acl_bad_C__Windows_SystemApps.txt -Tag apps     ->  C:\rm9\aclfix_apps.sddl (backup), C:\rm9\aclfix_apps.txt (log)
param([string]$List, [string]$Tag = 'x')
$sddl = "C:\rm9\aclfix_$Tag.sddl"; $log = "C:\rm9\aclfix_$Tag.txt"
Remove-Item $sddl, $log -ErrorAction SilentlyContinue
$paths = Get-Content $List -Encoding utf8 | Where-Object { $_ }
$w = New-Object System.IO.StreamWriter($sddl, $false, (New-Object System.Text.UTF8Encoding($false)))
$ok = 0; $fail = 0
foreach ($p in $paths) {
  $q = $p.TrimEnd('\')
  try { $w.WriteLine($q + '|' + (Get-Acl -LiteralPath $q).Sddl) } catch { }
  $r = & icacls.exe $q /reset 2>&1
  if ($LASTEXITCODE -eq 0) { $ok++ } else { $fail++; Add-Content $log ("FAIL " + $q + " : " + ($r -join ' ')) }
}
$w.Dispose()
Add-Content $log ("done: reset $ok, failed $fail of " + @($paths).Count)
