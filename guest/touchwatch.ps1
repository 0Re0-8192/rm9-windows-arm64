# run in the console user's session: log WM_POINTER touch messages (position, id) to C:\rm9\link\touchwatch.txt for -Seconds, to verify the virtual HID touch screen end to end
param([int]$Seconds = 60)
$out = 'C:\rm9\link\touchwatch.txt'
function Note($m) { [IO.File]::AppendAllText($out, $m + [Environment]::NewLine) }
Trap { Note ('ERR ' + $_); continue }
Note ('started ' + (Get-Date -Format HH:mm:ss))
Add-Type -AssemblyName System.Windows.Forms
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Windows.Forms;
using System.Runtime.InteropServices;
public class WatchForm : Form {
  [DllImport("user32.dll")] static extern bool GetPointerInfo(uint id, out POINTER_INFO pi);
  [DllImport("user32.dll")] static extern bool RegisterTouchWindow(IntPtr h, uint f);
  [StructLayout(LayoutKind.Sequential)] struct RID { public ushort page, usage; public uint flags; public IntPtr target; }
  [DllImport("user32.dll", SetLastError = true)] static extern bool RegisterRawInputDevices([In] RID[] d, uint n, uint size);
  [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr h, uint cmd, IntPtr data, ref uint size, uint hdr);
  public static int RawCount = 0;
  public void RegRaw() { RID[] r = new RID[] { new RID { page = 0x0D, usage = 0x04, flags = 0x100, target = Handle } }; bool ok = RegisterRawInputDevices(r, 1, (uint)Marshal.SizeOf(typeof(RID))); Log.AppendLine("RegisterRawInputDevices ok=" + ok); }
  [StructLayout(LayoutKind.Sequential)] public struct PT { public int x, y; }
  [StructLayout(LayoutKind.Sequential)] public struct POINTER_INFO { public uint type, id, frame, flags; public IntPtr src, hwnd; public PT px, hm, pxr, hmr; public uint t, hist; public int inp; public uint keys; public ulong perf; public uint btn; }
  public static System.Text.StringBuilder Log = new System.Text.StringBuilder();
  public static int Count = 0;
  protected override void WndProc(ref Message m) {
    if (m.Msg >= 0x245 && m.Msg <= 0x247) {
      uint id = (uint)(m.WParam.ToInt64() & 0xFFFF); POINTER_INFO pi; Count++;
      if (GetPointerInfo(id, out pi)) Log.AppendLine((m.Msg == 0x246 ? "DOWN " : m.Msg == 0x247 ? "UP   " : "MOVE ") + "id=" + id + " type=" + pi.type + " x=" + pi.pxr.x + " y=" + pi.pxr.y);
    }
    if (m.Msg == 0x201 || m.Msg == 0x202 || m.Msg == 0x240 || m.Msg == 0x2A3 || m.Msg == 0x11B) { Count++; Log.AppendLine("msg 0x" + m.Msg.ToString("X") + " lparam=" + m.LParam.ToInt64().ToString("X")); }
    if (m.Msg == 0x00FF) { RawCount++; uint sz = 0; GetRawInputData(m.LParam, 0x10000003, IntPtr.Zero, ref sz, 24); if (RawCount <= 5) Log.AppendLine("WM_INPUT size=" + sz); }
    base.WndProc(ref m);
  }
}
'@
$f = New-Object WatchForm
$f.FormBorderStyle = 'None'; $f.StartPosition = 'Manual'; $f.Bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds; $f.TopMost = $true; $f.ShowInTaskbar = $false
$f.Add_Shown({ $f.RegRaw(); Note ('shown bounds ' + $f.Left + ',' + $f.Top + ' ' + $f.Width + 'x' + $f.Height) })
Note ('form ready, screen ' + $f.Width + 'x' + $f.Height)
$t = New-Object System.Windows.Forms.Timer; $t.Interval = 500
$t.Add_Tick({ if ([WatchForm]::Log.Length -gt 0) { Note ([WatchForm]::Log.ToString().TrimEnd()); [void][WatchForm]::Log.Clear() } })
$t.Start()
$e = New-Object System.Windows.Forms.Timer; $e.Interval = $Seconds * 1000; $e.Add_Tick({ Note ('pointer messages seen: ' + [WatchForm]::Count + ' raw HID inputs: ' + [WatchForm]::RawCount); $f.Close() }); $e.Start()
[System.Windows.Forms.Application]::Run($f)
