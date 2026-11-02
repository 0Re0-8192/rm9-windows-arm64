# C:\rm9\link\gamesw.ps1 (SYSTEM, boot task rm9gamesw): the RedMagic shoulder "game switch" (TLMM gpio65, DT gpio_keys_nubia/game_sw; idle = 1) read through rm9io.sys.
# Logs every change to C:\rm9\link\gamesw.txt and runs C:\rm9\link\gamesw_on.cmd / gamesw_off.cmd if they exist (user-defined actions).  50 ms poll, 30 ms debounce.
param([int]$Seconds = 8640000)
. C:\rm9\link\rm9io.ps1
cmd /c "sc start rm9io" | Out-Null
$gpio = 65; $addr = [uint64]0xF100000 + 0x1000 * $gpio + 4
$log = 'C:\rm9\link\gamesw.txt'
function L($m) {
    $fs = New-Object IO.FileStream($log, [IO.FileMode]::Append, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
    $b = [Text.Encoding]::ASCII.GetBytes(("{0} {1}`r`n" -f (Get-Date -Format 'HH:mm:ss.fff'), $m)); $fs.Write($b, 0, $b.Length); $fs.Dispose()
}
function ReadSw { try { return ((Rm9Read $addr 1)[0] -band 1) } catch { return -1 } }
$state = ReadSw; L "start state=$state"
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $v = ReadSw
    if ($v -ge 0 -and $v -ne $state) {
        Start-Sleep -Milliseconds 30
        $v2 = ReadSw
        if ($v2 -eq $v) {
            $state = $v
            $name = if ($state -eq 0) { 'on' } else { 'off' }
            L "game switch -> $name (gpio=$state)"
            $cmd = "C:\rm9\link\gamesw_$name.cmd"
            if (Test-Path $cmd) { try { Start-Process cmd.exe -ArgumentList "/c `"$cmd`"" -WindowStyle Hidden } catch { L "action failed: $_" } }
        }
    }
    Start-Sleep -Milliseconds 50
}
