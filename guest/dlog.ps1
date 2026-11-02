# S:\rm9\dlog.ps1 <message> : append one line to C:\rm9\session\devstep.txt with write-through (survives a forced reset right afterwards)
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Msg)
New-Item -ItemType Directory -Force C:\rm9\session | Out-Null
$fs = New-Object IO.FileStream('C:\rm9\session\devstep.txt', [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
$b = [Text.Encoding]::ASCII.GetBytes("$(Get-Date -Format 'HH:mm:ss.ff') $($Msg -join ' ')`r`n"); $fs.Write($b, 0, $b.Length); $fs.Dispose()
