# C:\rm9\touch\fps.ps1 - runs once in the console user's session: how fast does the desktop compositor (DWM) think the screen refreshes?
#   DwmFlush() returns on every composition (vblank); report the rate over 120 calls, three times, plus the refresh rate Windows reports.
$out = 'C:\rm9\touch\fps.txt'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Fps {
  [DllImport("dwmapi.dll")] public static extern int DwmFlush();
  [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
  [DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr dc, int i);
  public static int Vrefresh() { IntPtr dc = GetDC(IntPtr.Zero); return GetDeviceCaps(dc, 116); }
}
'@
"$(Get-Date -Format 'HH:mm:ss') VREFRESH(GetDeviceCaps)=$([Fps]::Vrefresh())" | Out-File -Append -Encoding ascii $out
for ($r = 0; $r -lt 3; $r++) {
    Start-Sleep 5
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $n = 0
    for ($i = 0; $i -lt 120; $i++) { [void][Fps]::DwmFlush(); $n++ }
    $ms = $sw.ElapsedMilliseconds
    "$(Get-Date -Format 'HH:mm:ss') DwmFlush x$n in $ms ms = $([math]::Round($n * 1000 / [Math]::Max($ms, 1), 1)) Hz" | Out-File -Append -Encoding ascii $out
}
