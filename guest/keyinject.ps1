# C:\rm9\link\keyinject.ps1 (user session, HKLM Run rm9keys): turn the key mask published by keypoll.ps1 into Windows key events.
#   volume up   -> VK_VOLUME_UP     (down on press, up on release)
#   volume down -> VK_VOLUME_DOWN   (down on press, up on release)
#   power       -> Ctrl+Shift+Esc = Task Manager (on press).  Not sleep/shutdown on purpose: the phone cannot wake itself up again.
# Edit the three entries in $map to change what a key does.  Log: C:\rm9\keyinject.log
$cur = "C:\Users\Public\rm9shot\keys.cur"
$log = "C:\rm9\keyinject.log"
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Kb { [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra); }
'@
$VK_CTRL = 0x11; $VK_SHIFT = 0x10; $VK_ESC = 0x1B
function KeyDown($vk) { [Kb]::keybd_event([byte]$vk, 0, 0, [UIntPtr]::Zero) }
function KeyUp($vk) { [Kb]::keybd_event([byte]$vk, 0, 2, [UIntPtr]::Zero) }
function Log($m) { "$(Get-Date -Format 'MM-dd HH:mm:ss.fff') $m" | Out-File -Append -Encoding ascii $log }
# bit -> @(name, vk-list pressed together, hold while the key is held?)
$map = @{
    1 = @("volume up",   @(0xAF), $true)
    2 = @("volume down", @(0xAE), $true)
    4 = @("power (task manager)", @($VK_CTRL, $VK_SHIFT, $VK_ESC), $false)
}
# one injector per session: run.cmd (launch_in_session) and the HKLM Run value rm9keys can both start one, and two of them inject every key twice (2026-10-31)
$mx = New-Object Threading.Mutex($false, 'Local\rm9keyinject')
if (-not $mx.WaitOne(0)) { Log "key injector already running in this session: exit"; exit }
Log "key injector started"
$last = 0; $lastSeq = -1
while ($true) {
    try {
        $t = [IO.File]::ReadAllText($cur).Trim()
        $f = $t.Split(";")
        if ($f.Count -eq 2 -and [int]$f[0] -ne $lastSeq) {
            $lastSeq = [int]$f[0]
            $mask = [int]$f[1]
            foreach ($bit in 1, 2, 4) {
                $was = ($last -band $bit) -ne 0; $now = ($mask -band $bit) -ne 0
                if ($now -and -not $was) {
                    $e = $map[$bit]
                    foreach ($vk in $e[1]) { KeyDown $vk }
                    if (-not $e[2]) { [array]::Reverse($e[1]); foreach ($vk in $e[1]) { KeyUp $vk }; [array]::Reverse($e[1]) }
                    Log ("press   " + $e[0])
                } elseif ($was -and -not $now) {
                    $e = $map[$bit]
                    if ($e[2]) { foreach ($vk in $e[1]) { KeyUp $vk } }
                    Log ("release " + $e[0])
                }
            }
            $last = $mask
        }
    } catch { }
    Start-Sleep -Milliseconds 20
}
