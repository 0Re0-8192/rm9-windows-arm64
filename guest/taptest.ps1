# run in the console user's session: one synthetic tap with InjectTouchInput at (300,500) (to check that touchwatch.ps1 sees pointer messages at all)
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Tap {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential)] public struct POINTER_INFO { public uint pointerType, pointerId, frameId, pointerFlags; public IntPtr sourceDevice, hwndTarget; public POINT ptPixelLocation, ptHimetricLocation, ptPixelLocationRaw, ptHimetricLocationRaw; public uint dwTime, historyCount; public int InputData; public uint dwKeyStates; public ulong PerformanceCount; public uint ButtonChangeType; }
  [StructLayout(LayoutKind.Sequential)] public struct POINTER_TOUCH_INFO { public POINTER_INFO pointerInfo; public uint touchFlags, touchMask; public RECT rcContact, rcContactRaw; public uint orientation, pressure; }
  [DllImport("user32.dll", SetLastError = true)] public static extern bool InitializeTouchInjection(uint maxCount, uint mode);
  [DllImport("user32.dll", SetLastError = true)] public static extern bool InjectTouchInput(uint count, [In] POINTER_TOUCH_INFO[] c);
  public static POINTER_TOUCH_INFO Make(uint flags, int x, int y) { POINTER_TOUCH_INFO t = new POINTER_TOUCH_INFO(); t.pointerInfo.pointerType = 2; t.pointerInfo.pointerId = 7; t.pointerInfo.pointerFlags = flags; t.pointerInfo.ptPixelLocation.x = x; t.pointerInfo.ptPixelLocation.y = y; t.touchMask = 7; t.rcContact.l = x - 2; t.rcContact.r = x + 2; t.rcContact.t = y - 2; t.rcContact.b = y + 2; t.orientation = 90; t.pressure = 512; return t; }
}
'@
$a = [Tap]::InitializeTouchInjection(5, 1)
$d = [Tap]::InjectTouchInput(1, @([Tap]::Make(0x10000 -bor 0x2 -bor 0x4, 300, 500)))
$err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
Start-Sleep -Milliseconds 50
$m = [Tap]::InjectTouchInput(1, @([Tap]::Make(0x20000 -bor 0x2 -bor 0x4, 305, 505)))
Start-Sleep -Milliseconds 50
$u = [Tap]::InjectTouchInput(1, @([Tap]::Make(0x40000, 305, 505)))
[IO.File]::AppendAllText('C:\rm9\link\touchwatch.txt', "taptest init=$a down=$d (err=$err) move=$m up=$u" + [Environment]::NewLine)
