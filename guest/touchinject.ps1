# C:\Users\Public\rm9shot\touchinject.ps1 - runs in the console user's session: read touch.cur (written by touchpoll.ps1) and inject the contacts with InjectTouchInput.
#   raw panel coordinates: x 0..17856, y 0..39680 (portrait).  -Rotate: 0 = desktop is portrait like the panel; 90/270 = desktop is landscape (panel rotated).
param([int]$Seconds = 900, [int]$Rotate = -1)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Inj {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential)] public struct POINTER_INFO {
    public uint pointerType, pointerId, frameId, pointerFlags; public IntPtr sourceDevice, hwndTarget;
    public POINT ptPixelLocation, ptHimetricLocation, ptPixelLocationRaw, ptHimetricLocationRaw;
    public uint dwTime, historyCount; public int InputData; public uint dwKeyStates; public ulong PerformanceCount; public uint ButtonChangeType; }
  [StructLayout(LayoutKind.Sequential)] public struct POINTER_TOUCH_INFO { public POINTER_INFO pointerInfo; public uint touchFlags, touchMask; public RECT rcContact, rcContactRaw; public uint orientation, pressure; }
  [DllImport("user32.dll", SetLastError = true)] public static extern bool InitializeTouchInjection(uint maxCount, uint mode);
  [DllImport("user32.dll", SetLastError = true)] public static extern bool InjectTouchInput(uint count, [In] POINTER_TOUCH_INFO[] contacts);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
  public static POINTER_TOUCH_INFO Make(uint id, uint flags, int x, int y) {
    POINTER_TOUCH_INFO t = new POINTER_TOUCH_INFO();
    t.pointerInfo.pointerType = 2; t.pointerInfo.pointerId = id; t.pointerInfo.pointerFlags = flags;
    t.pointerInfo.ptPixelLocation.x = x; t.pointerInfo.ptPixelLocation.y = y;
    t.touchMask = 0x4 | 0x2 | 0x1;   // contact area, orientation, pressure
    t.rcContact.l = x - 2; t.rcContact.r = x + 2; t.rcContact.t = y - 2; t.rcContact.b = y + 2;
    t.orientation = 90; t.pressure = 512;
    return t;
  }
}
'@
New-Item -ItemType Directory -Force C:\Users\Public\rm9shot | Out-Null
$log = 'C:\Users\Public\rm9shot\touchinject.log'
# physical pixels: without this a DPI-unaware process sees the desktop shrunk by the scale factor (125% -> 893x1984) and the injected points land in the wrong place
$dpi = $false
try { $dpi = [Inj]::SetProcessDpiAwarenessContext([IntPtr](-4)) } catch {}
if (-not $dpi) { [void][Inj]::SetProcessDPIAware() }
$W = [Inj]::GetSystemMetrics(0); $H = [Inj]::GetSystemMetrics(1)
if ($Rotate -lt 0) { $Rotate = if ($W -gt $H) { 90 } else { 0 } }
"start W=$W H=$H dpiAware=$dpi rotate=$Rotate init=$([Inj]::InitializeTouchInjection(10, 1))" | Add-Content $log
$UP = 0x40000; $DOWN = 0x10000 -bor 0x2 -bor 0x4; $UPD = 0x20000 -bor 0x2 -bor 0x4
$active = @{}      # id -> last (x,y)
$script:tr = 0
$last = 0
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
    $line = $null
    try { $line = [IO.File]::ReadAllText('C:\Users\Public\rm9shot\touch.cur') } catch {}
    if ($line -and $line.EndsWith(';')) {
        $p = $line.Split(';')
        $seq = [uint32]$p[0]
        if ($seq -ne $last) {
            $last = $seq
            $cnt = [int]$p[1]
            $now = @{}
            for ($i = 0; $i -lt [Math]::Min($cnt, 5); $i++) {
                $q = $p[2 + $i].Split(',')
                $id = [int]$q[0]; $rx = [double]$q[1]; $ry = [double]$q[2]
                if ($Rotate -eq 0)      { $x = $rx / 17856 * $W;        $y = $ry / 39680 * $H }
                elseif ($Rotate -eq 90) { $x = (1 - $ry / 39680) * $W;  $y = $rx / 17856 * $H }
                else                    { $x = $ry / 39680 * $W;        $y = (1 - $rx / 17856) * $H }
                $now[$id] = @([Math]::Min([Math]::Max([int]$x, 0), $W - 1), [Math]::Min([Math]::Max([int]$y, 0), $H - 1))
            }
            $list = New-Object System.Collections.Generic.List[Inj+POINTER_TOUCH_INFO]
            foreach ($id in $now.Keys) {
                $fl = if ($active.ContainsKey($id)) { $UPD } else { $DOWN }
                $list.Add([Inj]::Make([uint32]$id, [uint32]$fl, $now[$id][0], $now[$id][1]))
            }
            foreach ($id in @($active.Keys)) {
                if (-not $now.ContainsKey($id)) { $list.Add([Inj]::Make([uint32]$id, [uint32]$UP, $active[$id][0], $active[$id][1])) }
            }
            $active = $now
            if ($list.Count -gt 0) {
                $ok = [Inj]::InjectTouchInput([uint32]$list.Count, $list.ToArray())
                if ($script:tr -lt 600 -and (Test-Path 'C:\Users\Public\rm9shot\trace.on')) { $script:tr++; $d = ($list | ForEach-Object { '{0}:{1:X}@{2},{3}' -f $_.pointerInfo.pointerId, $_.pointerInfo.pointerFlags, $_.pointerInfo.ptPixelLocation.x, $_.pointerInfo.ptPixelLocation.y }) -join ' '; ('{0} seq={1} n={2} ok={3} err={4} {5}' -f $sw.ElapsedMilliseconds, $seq, $list.Count, $ok, $(if ($ok) { 0 } else { [Runtime.InteropServices.Marshal]::GetLastWin32Error() }), $d) | Add-Content 'C:\Users\Public\rm9shot\inject_trace.txt' }
                if (-not $ok) {
                    "inject failed err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error()) seq=$seq" | Add-Content $log
                    # state mismatch (e.g. a contact id that Windows does not know): release everything and start over from the next frame
                    $rel = New-Object System.Collections.Generic.List[Inj+POINTER_TOUCH_INFO]
                    foreach ($id in $now.Keys) { $rel.Add([Inj]::Make([uint32]$id, [uint32]$UP, $now[$id][0], $now[$id][1])) }
                    if ($rel.Count -gt 0) { [void][Inj]::InjectTouchInput([uint32]$rel.Count, $rel.ToArray()) }
                    $active = @{}
                }
            }
        }
    }
    Start-Sleep -Milliseconds 2
}
