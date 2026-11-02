# aclaudit.ps1 - files whose DACL lacks the ALL APPLICATION PACKAGES (S-1-15-2-1) ACE (AppContainer apps get access denied on those; typical for ACLs left as "Everyone:F" by the earlier offline rollback).
# Output: C:\rm9\aclaudit.txt (counts) and C:\rm9\acl_bad_<name>.txt (full lists)
param([string[]]$Roots = @('C:\Windows\SystemApps', 'C:\Windows\SystemResources'))
$o = 'C:\rm9\aclaudit.txt'
function W($m) { Add-Content -Path $o -Value $m -Encoding utf8 }
$ac = New-Object System.Security.Principal.SecurityIdentifier('S-1-15-2-1')
foreach ($r in $Roots) {
  $name = ($r -replace '[:\\ ]', '_')
  $list = New-Object System.Collections.Generic.List[string]
  $n = 0; $bad = 0; $t0 = Get-Date
  $items = @(Get-Item $r -Force) + @(Get-ChildItem $r -Recurse -Force -ErrorAction SilentlyContinue)
  foreach ($it in $items) {
    $n++
    try {
      $sd = $it.GetAccessControl('Access')
      $has = $false
      foreach ($ace in $sd.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) { if ($ace.IdentityReference -eq $ac) { $has = $true; break } }
      if (-not $has) { $bad++; [void]$list.Add($it.FullName + $(if ($it.PSIsContainer) { '\' } else { '' })) }
    } catch { }
  }
  [IO.File]::WriteAllLines("C:\rm9\acl_bad_$name.txt", $list)
  W ("{0}: {1} items, {2} without ALL APPLICATION PACKAGES ({3:N0} s)" -f $r, $n, $bad, ((Get-Date) - $t0).TotalSeconds)
}
W 'done'
