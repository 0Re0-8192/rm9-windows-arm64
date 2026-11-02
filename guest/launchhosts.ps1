# launchhosts.ps1 - start the shell hosts the way the shell does (activate the AppX app ids) as the logged-on user session via the already-used launch_in_session path is not needed here:
# the hosts are started by explorer / ShellExperienceHost on demand; here we only try to activate them with the package family and report what happens.  Output C:\rm9\launchhosts.txt
$o = 'C:\rm9\launchhosts.txt'; Remove-Item $o -ErrorAction SilentlyContinue
function W($m) { Add-Content -Path $o -Value $m -Encoding utf8 }
W ("now " + (Get-Date))
foreach ($a in 'Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy!App','MicrosoftWindows.Client.CBS_cw5n1h2txyewy!CortanaUI','MicrosoftWindows.Client.CBS_cw5n1h2txyewy!InputApp') {
  try { Start-Process "shell:AppsFolder\$a" -ErrorAction Stop; W "started $a" } catch { W "start FAILED $a : $($_.Exception.Message)" }
}
Start-Sleep 20
foreach ($n in 'StartMenuExperienceHost','SearchHost','TextInputHost') {
  $p = Get-Process -Name $n -ErrorAction SilentlyContinue
  W ("proc {0}: {1}" -f $n, $(if ($p) { ($p | ForEach-Object { "pid$($_.Id) session$($_.SessionId)" }) -join ', ' } else { 'not running' }))
}
