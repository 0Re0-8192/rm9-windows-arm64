# run on the Winlogon desktop (launch_winlogon.ps1): wake the display (mouse move + SC_MONITORPOWER on), wait, then dump the screen like shotraw.ps1
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Wk {
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, IntPtr e);
}
'@
for ($i = 0; $i -lt 3; $i++) {
    [Wk]::mouse_event(1, 5, 5, 0, [IntPtr]::Zero)
    [void][Wk]::SendMessage([IntPtr]0xFFFF, 0x0112, [IntPtr]0xF170, [IntPtr](-1))
    Start-Sleep -Milliseconds 700
}
Start-Sleep 2
& C:\rm9\link\shotraw.ps1
